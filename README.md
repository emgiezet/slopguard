# Slop Guard

Anti-pattern detection and gate for agent-written code.

Slop Guard runs as a plugin for Claude Code, Codex CLI and Grok, wrapping every
edit in three detection layers: a fast synchronous gate on every write, a
background medium-tier check after each edit batch, and a slow gate at turn end
before the agent declares completion.  It also ships as a standalone PyPI
package so you can call `slopguard` directly from scripts and CI.

> **Status:** the PyPI package is not yet published.  Install from source
> (see [As a PyPI package](#as-a-pypi-package)) or use the plugin directly.
> Once published: `pip install slopguard`.

---

## Contents

- [Installation](#installation)
  - [As a Claude Code plugin](#as-a-claude-code-plugin)
  - [As a PyPI package](#as-a-pypi-package)
- [Configuration](#configuration)
- [What runs and when](#what-runs-and-when)
- [Stop gate and enforcement modes](#stop-gate-and-enforcement-modes)
- [Prevention skills](#prevention-skills)
- [CLI reference](#cli-reference)
- [Contributing](#contributing)
- [Release process](#release-process)

---

## Installation

### As a Claude Code / Codex / Grok plugin (hooks-based)

Slop Guard is a **hooks-based plugin**, not an MCP server.  `claude mcp add`
does not apply.

**Local checkout install:**

```bash
# Clone to a permanent location on your machine
git clone <repo-url> ~/.local/share/claude/plugins/slop-guard
```

Then reference the checkout in your `~/.claude/settings.json` or project
`.claude/settings.json`.  The exact key depends on your Claude Code version;
the plugin manifest lives at `.claude-plugin/plugin.json` and hook definitions
at `hooks/hooks.json`.  `CLAUDE_PLUGIN_ROOT` is set by the host to the
checkout directory; no manual environment setup is required.

**For the omp harness:** reference the checkout path as `"source"` in your
`.omp-plugin/marketplace.json` plugin entry (see the existing entry in this
repo for the exact shape).

> **omp adapter caveat:** `extensions/omp.mjs` currently wires only
> `PreToolUse` and `SessionStart` events.  The fast/medium `PostToolUse`
> detection tiers and the `Stop` gate are **not** forwarded under omp.

**For Codex CLI or Grok:** see `plugin.json` and your host's plugin
documentation for the installation method.

### As a PyPI package

**Requires:** Python ≥ 3.9, `bash`, `jq`.

```bash
pip install slopguard
slopguard doctor              # check which tools are available for your stacks
slopguard doctor --install    # install pinned tools for detected stacks
```

The wheel bundles the complete plugin tree (hooks, rules, skills, configs,
tools lockfile) under `slopguard/_plugin/`.  The `slopguard` entry point
discovers this bundled root automatically — no `SLOPGUARD_PLUGIN_DIR` or
`CLAUDE_PLUGIN_ROOT` override is required.

**Isolated root:** the installed entry point **always** sets `CLAUDE_PLUGIN_ROOT`
to the bundled `_plugin/` directory, overwriting any inherited value.  This
ensures the CLI sources its own assets even when run inside an environment where
a plugin host has already exported `CLAUDE_PLUGIN_ROOT`.  Plugin hosts invoke
`bin/slopguard` directly from the checkout; they never call the PyPI entry point.

**Development / source checkout** — use `bin/slopguard` directly; it derives
its own `PLUGIN_ROOT` from `$SCRIPT_DIR` at startup.  Running `pip install -e .`
gives you the `slopguard` command on your `PATH`; it falls back to the project
root automatically when the wheel-bundled `_plugin/` directory is absent.

---

## Configuration

Three files let you tune Slop Guard without forking it.

**`.slopguard.json`** — declare which stacks the guard covers and, in a
monorepo, which paths belong to which stack.  If absent, stacks are detected
automatically.  See `docs/recommended-project-settings.json` for a full
example snippet.

**`.slopguard/mapping/<tool>.yaml`** — retune or extend rules for tools the
guard already runs.  Format is identical to `rules/mapping/<tool>.yaml`; a
project entry patches the plugin entry field by field.  Lowering a severity
is allowed (silencing a noisy rule is a legitimate project decision) and every
downgrade is counted and reported.

```yaml
# .slopguard/mapping/sqlfluff.yaml
rules:
  AM04:
    ap_id: AP-SQL-MAINT-002
    severity: warn
    category: maintainability
    cwe: ""
  S608:
    severity: error
```

**`.slopguard/tools/<name>.yaml`** — bring in a linter the guard does not pin.
The guard only runs a binary your project already installs or whose `sha256`
you declared — it never installs a descriptor's tool itself.

```yaml
# .slopguard/tools/sqlfluff.yaml
name: sqlfluff
tier: fast
match:
  globs: ["**/*.sql"]
  stacks: [sql]
resolve:
  project: [".venv/bin/sqlfluff", "vendor/bin/sqlfluff"]
run:
  args: ["lint", "--format", "json", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[] | .violations[]? | {rule: .code, line: .line_no, message: .description}'
```

Every file under `.slopguard/` requires human approval to change (the
`pre-write` hook asks, same as `.slopguard.json`).

**Adopt a baseline config** to opt in to full reporting for a tool (security
overlay only reports security findings without a project config):

```bash
slopguard adopt-config ruff        # copies configs/baseline/ruff.toml
slopguard adopt-config mypy        # writes .slopguard/tools/mypy.yaml
slopguard adopt-config pylint      # writes .slopguard/tools/pylint.yaml
slopguard adopt-config             # list what is not yet adopted
```

**Plugin options** (set via the Claude Code plugin options dialog or in
`.slopguard.json`):

| Option | Values | Default |
|---|---|---|
| `enforcement_mode` | `advisory \| balanced \| strict` | `balanced` |
| `stop_gate` | `true \| false` | `true` |
| `sast_engine` | `opengrep \| semgrep \| none` | `opengrep` |
| `allow_network` | `true \| false` | `false` |
| `tool_source` | `project-first \| plugin-only \| project-only` | `project-first` |
| `config_source` | `overlay \| full \| project-only` | `overlay` |
| `require_docs_lookup` | `true \| false` | `true` |
| `dependency_freshness` | `off \| warn \| error` | `warn` |
| `dependency_cooldown_days` | integer (string) | `"3"` |

---

## What runs and when

Slop Guard wraps every edit in three layers, each at a different cost point.

### Fast tier — on every write, foreground (p95 < 2 s)

Synchronous `PostToolUse` hook.  Runs immediately after each file write or
edit and returns findings to the agent before it continues.

Tools: Ruff (Python), ESLint without type-info (JS/TS), hadolint (Dockerfile),
kube-linter (Kubernetes YAML), zizmor (GitHub Actions).

Findings are filtered to the **changed lines only** — existing problems in
unchanged code are not re-reported every turn.  A missing tool is skipped
silently with a one-time session note; it never blocks the write.

### Medium tier — after the edit batch, background (< 60 s)

Async `PostToolUse` hook with `asyncRewake`.  Starts after the fast hook; the
agent continues working while it runs.  Only wakes the agent back if it finds
new problems at `error` severity or above.

Tools: PHPStan (PHP), golangci-lint with `--new-from-rev` (Go), ESLint with
type-info (JS/TS), tflint (Terraform), Checkov per-file (IaC), Opengrep with
the plugin's own rules (all stacks), jscpd directory-scoped (duplication).

A three-second debounce collapses a rapid edit batch into one run.

### Slow tier — at turn end, Stop gate (< 5 min)

`Stop` hook.  Runs before the agent declares the turn complete.  Covers
analysis too expensive for per-file runs: Psalm taint-analysis (PHP), Checkov
on the whole changed directory (IaC), Betterleaks on the full session diff.

Also re-runs `slopguard deps-check` when any dependency manifest changed, and
reports (never blocks) if framework files were edited without a Context7
documentation lookup in the session.

---

## Stop gate and enforcement modes

The Stop gate holds the agent on the current turn until every blocker in
changed code is resolved.

| Mode | Blockers | Errors | Warnings |
|---|---|---|---|
| `advisory` | `additionalContext` only | `additionalContext` only | `additionalContext` |
| `balanced` (default) | blocks turn end | `additionalContext` in Stop | `additionalContext` |
| `strict` | blocks turn end | blocks turn end | `additionalContext` |

**Loop protection:** the same blocker in the same file can hold the agent at
most twice in a row.  After that it is downgraded to a warning and a message
is shown to the user — so a genuinely unresolvable issue never spins the
agent indefinitely.

To disable the Stop gate for a project, set `stop_gate: false` in
`.slopguard.json` or in the plugin options.

---

## Prevention skills

Alongside runtime checks, Slop Guard loads language-specific prevention skills
that put the rules in the agent's context before it writes any code.

| Skill | Loads when editing |
|---|---|
| `php-antipatterns` | `*.php`, `*.blade.php` |
| `go-antipatterns` | `*.go` |
| `python-antipatterns` | `*.py` |
| `ts-react-antipatterns` | `*.ts`, `*.tsx` |
| `node-antipatterns` | `*.js`, `*.mjs`, `*.cjs` |
| `sql-antipatterns` | `*.sql` |
| `iac-antipatterns` | `*.tf`, `*.yaml`, `*.yml`, `Dockerfile` (IaC context) |
| `auth-antipatterns` | auth, login, session, token, password and OAuth paths |
| `agent-discipline` | always — AP-AGENT-001 through AP-AGENT-011 |

`auth-antipatterns` is the one catalogue that is not a language: token entropy,
reset-token storage and TTL, password hashing (argon2id, bcrypt cost, scrypt),
session rotation and invalidation, JWT verification, re-authentication before a
credential change, rate limits, account enumeration, OAuth2 state and PKCE, OTP
attempt limits.

**Always-on rules:** AP-AGENT-002 asks only when a required *test* gate is
weakened (a coverage threshold that drops or disappears, a test step removed
from CI, or an edit to Slop Guard's own configuration).  AP-AGENT-004 always
blocks `curl | sh` and global installs, but a routine dependency add proceeds
with a note and escalates to `ask` only when the package name resembles a
popular one.

Session banners shrink once read.  The always-on digest prints in full the
first time a repository starts a session and becomes a one-line pointer
afterwards (`SLOPGUARD_DIGEST=full` forces the long form back).

Tier-2 stacks (JVM, C#, Ruby, Rust) load their own skills with Opengrep-backed
detection.  `SessionStart` says which tier each detected stack runs at, so
silence from the detector is never mistaken for a clean codebase.

### Agent commands

`/slop-guard:secure-review` runs a read-only security-reviewer subagent over
the current session's changed files.  It cannot write or edit — it only
reports.

`/slop-guard:deslop <path>` runs an editing subagent over a file or directory,
removing duplicate blocks and dead code.  Without `--tests <cmd>` it performs
pure deletions only.  `--dry-run` lists what would be changed without writing
anything.

---

## CLI reference

```
slopguard doctor             report tool status for the project's stacks
slopguard doctor --install   install or update the tools those stacks need
slopguard doctor --all       widen either command to every pinned tool
slopguard adopt-config       list tools without a project config
slopguard adopt-config <t>   copy the baseline config for <t> into the project
slopguard note-docs          record a Context7 lookup (reads hook JSON on stdin)
slopguard deps-check         check dependency freshness against registries
slopguard deps-check --json  emit a JSON array of verdicts (CI-friendly)
slopguard version            print version
slopguard help               full usage
```

`deps-check` environment knobs:

| Variable | Purpose |
|---|---|
| `CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK` | Must be `true` to enable registry queries |
| `CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS` | `off \| warn \| error` |
| `CLAUDE_PLUGIN_OPTION_DEPENDENCY_COOLDOWN_DAYS` | Freshness cooldown in days |
| `SLOPGUARD_FETCH_CMD` | Override HTTP fetch for offline testing |
| `SLOPGUARD_REGISTRIES_JSON` | Override registries file path |

**Tool resolution order** (when `tool_source=project-first`):

1. Project binary — `vendor/bin`, `node_modules/.bin`, `.venv/bin`, `go tool -n`
2. Plugin binary — `${CLAUDE_PLUGIN_DATA}/tools/<name>/current/<name>`, accepted
   only when the version matches the lockfile
3. PATH binary — accepted only when the version matches the lockfile

---

## Contributing

See `docs/slop-guard-spec.md` for the full specification.
See `.claude/playbooks/add-rule.md` for the rule-addition sequence.
See `.claude/rules/catalog.md` for catalogue conventions and verification.

### Adding a rule in brief

1. Add one entry to `rules/catalog.yaml` (`AP-*` id, fields per §4.9 of the spec).
2. If the rule has detection: add a mapping entry in `rules/mapping/<tool>.yaml`
   and fixture files in `tests/fixtures/<lang>/{bad,good}/`.
3. Regenerate skills: `scripts/gen-skills`.
4. Add a changelog entry under `## Unreleased`.
5. Verify: `bash tests/catalog_test.sh && CI= bash tests/run-tests`.

### Running the test suite

```bash
bash tests/run-tests            # unit + bash hook tests (needs jq)
bash tests/tool-integration     # integration tests (needs installed tools)
pytest tests/python/ -v         # installed-artifact Python tests (builds wheel)
```

The Python tests build a wheel from source and install it in a temporary
virtual environment — no prior installation needed, but `build` and `hatchling`
must be available (they are installed automatically if missing).

Use the `SLOPGUARD_TEST_BIN` env var to skip the build step and point at an
already-installed binary:

```bash
pip install dist/slopguard-*.whl
SLOPGUARD_TEST_BIN="$(which slopguard)" pytest tests/python/ -v
```

---

## Release process

Slop Guard has two version fields that must be kept in sync:

| File | Field |
|---|---|
| `pyproject.toml` | `[project] version` |
| `.claude-plugin/plugin.json` | `"version"` |
| `plugin.json` | `"version"` |

**To release a new version:**

1. Bump the version string in all three files in a single commit.
2. Update `CHANGELOG.md`: move `## Unreleased` items under a new
   `## <version> — <date>` heading.
3. Merge the commit to `main`.
4. Push a tag: `git tag v<version> && git push origin v<version>`.

The `publish.yml` GitHub Actions workflow triggers on the tag, builds the
wheel and sdist, verifies the tag matches `pyproject.toml`, and publishes to
PyPI via **Trusted Publishing** (OIDC — no stored API token).

**First-time PyPI setup (owner action):**

1. In repo Settings → Environments, create an environment named
   `pypi-publish`.  Add a deployment protection rule if desired.
2. On PyPI, under the `slopguard` project's Publishing tab, add a Trusted
   Publisher entry:
   - Owner: `<your-github-org-or-user>`
   - Repository: `slop-guard` (this repo's name)
   - Workflow: `publish.yml`
   - Environment: `pypi-publish`
3. No secret or API token is needed after this — the workflow handles
   authentication via OIDC.

---

## License

MIT — see `LICENSE`.

Third-party tool attributions are in `THIRD_PARTY_NOTICES.md`.
