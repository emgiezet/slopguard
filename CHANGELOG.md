# Changelog

All notable changes to Slop Guard will be documented in this file.

## Unreleased
- **Extension mechanism: `.slopguard/`** (2026-09-23)
  - `lib/ext.sh` (new): `ext_dir` (extension root, honoring `SLOPGUARD_EXT_DIR`), `ext_load_mapping` (merges plugin + project mapping overrides, outputs NDJSON per rule), `ext_tools` (loads and validates tool descriptors, returns one NDJSON object per descriptor with `resolved` and `status` fields), `ext_validate` (exit 0 if a descriptor or mapping file is structurally valid), `ext_override_counts` (total overrides + severity downgrade count).
  - Two extension classes: **(A)** `.slopguard/mapping/<tool>.yaml` — project patches plugin's `rules/mapping/<tool>.yaml` field by field (same schema; partial entries allowed); **(B)** `.slopguard/tools/<name>.yaml` — full descriptor for a linter the plugin does not pin.
  - Security rules enforced in `ext_validate` and `ext_tools`: `run.args` must be an array (no shell-string command); `parse.jq` is a jq expression evaluated by `jq -e`; binary resolution requires `resolve.project` paths (relative, must exist and be executable) or a PATH binary matching `resolve.path_sha256`; the plugin never installs a descriptor's tool (`doctor --install` serves `tools.lock.json` only).
  - Refusal cases: no resolution spec (`refused:no-resolve`), sha256 mismatch (`refused:sha256-mismatch`), `name` does not match filename (`refused:name-mismatch`), name collides with a pinned tool (`refused:pinned-tool-collision`), unparseable file (`refused:invalid`).
  - Severity downgrade counting: `ext_override_counts` emits `<total_overrides> <severity_downgrades>`. Rank for comparison: `blocker` > `error` > `warn` > `info`. Lowering severity is allowed and counted; silent systematic downgrading is AP-AGENT-002.
  - No `~/.config` scope — deliberately rejected. Configuration that does not travel with the repo makes developer results differ from CI.
  - `.slopguard/**` added to `pre-write` protected list as `ask` (§7.2C) — same protection as `.slopguard.json`.
  - `docs/slop-guard-spec.md`: §7.8 (new) documents the extension mechanism end to end; §9.1 updated — descriptor tools are resolution step 4, after pinned plugin tools; TOC updated. D23 added to `docs/decisions.md`.
- **Etap 2 (partial): fast-tier detection** (2026-09-23)
  - `lib/diff.sh` (new): `diff_changed_ranges`, `diff_is_untracked`, `diff_line_in_ranges` — implements §2 Z2 changed-lines filter using `git diff -U0`; untracked files are judged whole.
  - `lib/dispatch.sh` (new): `dispatch_fast` dispatcher; routes files to fast-tier tools by extension and filename pattern; per-tool timeout (`SLOPGUARD_FAST_TOOL_TIMEOUT`, default 8 s, §2 Z6 fail-open on timeout or missing binary); §2 Z2 line filter applied per finding category; fingerprint-based session deduplication; findings persisted via `finding_add`.
  - `hooks/post-write` (new): `PostToolUse` hook runs `dispatch_fast`, formats output per §4.7 (one line per finding, grouped by file, max 20 findings, < 4000 chars), enforces §4.6 modes (`advisory` → `additionalContext`; `balanced`/`strict` → `exit 2` + stderr on blocker/error, `additionalContext` on warn).
  - `hooks/hooks.json`: `PostToolUse` entry added — matcher `Write|Edit|MultiEdit|NotebookEdit`, calls `slopguard post-write --tier=fast`, timeout 20 s.
  - `bin/slopguard`: `post-write` subcommand added (sources `lib/diff.sh` and `lib/dispatch.sh`, then delegates to `hooks/post-write`).
  - Five fast-tier tools wired (all already in `tools.lock.json`):
    - **Ruff** (`ruff check --config $CONFIG --output-format=json --no-fix --exit-zero $FILE`) — Python.
    - **ESLint without type-info** (`eslint --config $CONFIG --format json --no-warn-ignored $FILE`) — JS/TS.
    - **hadolint** (`hadolint --config $CONFIG -f json $FILE`) — Dockerfile.
    - **kube-linter** (`kube-linter lint --config $CONFIG --format json $FILE`) — Kubernetes YAML.
    - **zizmor** (`zizmor --config $CONFIG --format json --offline $FILE`) — GitHub Actions YAML.
  - `rules/mapping/{ruff,eslint,hadolint,kube-linter,zizmor}.yaml` (new): YAML mapping files (parsed by awk in `dispatch_map_lookup`) linking tool rule IDs to `AP-*` ids, severity, category, and CWE.
  - `tests/dispatch_test.sh` (new): 36 offline assertions covering mapping lookups per tool, diff-filter (changed line reported, unchanged maint/perf finding filtered, untracked file judged whole), fail-open (missing tool, timeout), 20-finding cap, fingerprint deduplication, routing by extension, end-to-end §4.7 message format.
  - Fixtures added: `tests/fixtures/{python,ts,docker,kubernetes,ci}/bad/` — one bad fixture per wired tool.
  - Remaining fast-tier tools (not yet in `tools.lock.json`, wiring blocked until Etap 0 pinning): `kubeconform`, `actionlint`, `squawk`, `sqlfluff`, `terraform fmt`/`tofu fmt`, `pint`/`php-cs-fixer`.
  - `docs/slop-guard-spec.md` §11.3 updated to record what Etap 2 delivered and what remains.

- `lib/deps.sh` — three new manifest parsers and crates.io re-activation:
  - `deps_fetch` now sends `User-Agent: slopguard/0.1.0 (+https://github.com/emgiezet/aisdlc)` on every `curl` request; crates.io requires this header and returns HTTP 403 without it.
  - `_deps_parse_cargo` (new): parses `Cargo.toml` `[dependencies]`, `[dev-dependencies]`, `[build-dependencies]`, `[workspace.dependencies]`, and `[target.*.dependencies]` sections; handles simple `pkg = "version"` and single-line inline-table `pkg = { version = "x", ... }` forms; skips workspace, path, git, and multi-line entries with a counted note to stderr.
  - `_deps_parse_pypi` (new): dispatcher for Python manifests. `_deps_parse_requirements` handles `requirements*.txt` (strips pip options, VCS lines, environment markers; normalises package names per PEP 503 — lowercase, `[-_.]+` → `-` — before the registry lookup; emits first version constraint before `,`). `_deps_parse_pyproject` handles both `[project] dependencies = [...]` (PEP 621) and `[tool.poetry.dependencies]` / `[tool.poetry.group.*.dependencies]` (Poetry) using a single-pass awk state machine; Poetry inline-table deps with a `version` key are extracted, those without (path, git) are skipped silently. `setup.py` and `setup.cfg` are skipped with a note (require a Python interpreter).
  - `_deps_parse_pom` (new): awk state machine over multi-line `<dependency>` blocks in `pom.xml`; outputs registry key `g:<groupId>+AND+a:<artifactId>` (Maven Central Solr syntax); skips entries whose `<version>` is a property reference (`${...}`) or missing (BOM-managed) with a counted note to stderr.
  - The `pypi` and `maven` skip-blocks in `deps_check_main` are removed; both ecosystems are now fully parsed. In human-readable mode, parser stderr (skip notes) is no longer suppressed so counted notes reach the terminal.
- `rules/registries.json`: `crates` entry re-added (endpoint `https://crates.io/api/v1/crates/{package}`, `latest_jq: .crate.max_stable_version`, `published_jq: .crate.updated_at`; verified live against `serde` — returns `1.0.229`/`2026-07-18T23:05:13.266456Z`). `pypi.manifests` updated to `["pyproject.toml", "requirements*.txt"]` (glob pattern, drops `setup.py`/`setup.cfg`).
- `docs/slop-guard-spec.md` §7.7: added ecosystem coverage table documenting all 8 parsers, their manifest files, parsing strategy, and deliberate skip cases; User-Agent requirement for crates.io, PEP 503 normalisation, and Maven Solr key format documented.
- `tests/deps_test.sh`: 25 new assertions (sections 9–12) covering cargo, requirements.txt, pyproject.toml (PEP 621 + Poetry), and pom.xml parsers — unit tests for name/version extraction, PEP 503 normalisation, skip notes, and end-to-end verdicts per ecosystem. Suite: 269 total.
- Grok runtime support: `lib/hook.sh` detects Grok via a compound condition on `GROK_PLUGIN_ROOT` and `CLAUDE_PLUGIN_ROOT` (presence of `GROK_PLUGIN_ROOT` alone is insufficient — a stale inherited variable in a Claude session would cause every deny to be silently ignored). `hook_input` normalizes Grok's camelCase event fields (`sessionId`, `hookEventName`, `toolName`, `toolInput`) to snake_case at the boundary so all policy scripts remain host-agnostic. `hook_deny`, `hook_secret_deny`, `hook_ask`, `hook_allow`, `hook_context`, and `hook_message` emit the host-correct envelope: Grok uses `{"decision":"deny","reason":…}` and exit-0 for allow; `hook_ask` becomes deny on Grok (fail-closed). `lib/state.sh`: `CLAUDE_PLUGIN_DATA` falls back to `GROK_PLUGIN_DATA` when the latter is set. `bin/slopguard`: seeds `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` from `GROK_PLUGIN_ROOT`/`GROK_PLUGIN_DATA` at startup, making the rest of the dispatcher host-agnostic. No `hooks/*` script required changes. Fixtures: `tests/hook-contract/grok-pre-tool-bash.json`, `tests/hook-contract/grok-pre-tool-write.json` (camelCase, as Grok sends them). Decision D22 recorded.
- `hooks/pre-write` + `bin/slopguard note-docs`: the Context7 memory is now wired end to end.
  A lookup that matches a framework the project runs records `<context7-query>@<major.minor>`;
  the first-edit instruction is suppressed when the agent already consulted the docs in this
  session (`docs_seen`) or in an earlier one at the same minor (`docs_recall`). A minor bump
  invalidates the record and the instruction returns. The blocker-checks sentence is never
  suppressed.
- `scripts/validate-configs`: a missing linter is no longer a validation failure. Default run
  exits 0 with `N skipped (not validated — tools absent)`; `--strict` (used by CI via the
  `CONFIG_STRICT` Makefile variable, which keys off `CI`) restores the old behaviour. Fixes
  `make validate` being unpassable on any machine without all 11 linters — and, because
  `validate` depends on `validate-slopguard`, silently skipping every `plugins/sdlc` check.
- `rules/registries.json` (new): package-registry endpoints for dependency-freshness checks — one entry per ecosystem (`npm`, `packagist`, `pypi`, `crates`, `rubygems`, `nuget`, `go`, `maven`); each entry carries `manifests`, `url` (with `{package}` placeholder), `latest_jq` and `published_jq` expressions; ecosystems whose endpoints could not be verified live are omitted rather than guessed.
- `rules/stacks.json`: new optional field `context7` on seven framework tags (`laravel`, `symfony`, `doctrine`, `react`, `vite`, `express`, `terraform`) — human-readable query for `mcp__context7__resolve-library-id`; never a hardcoded library id.
- `lib/docs.sh` (new): `docs_note` / `docs_seen` (case-insensitive, substring-tolerant session-level deduplication into `docs-lookups.json`); `docs_remember` / `docs_recall` (cross-session memory at `${CLAUDE_PLUGIN_DATA}/docs-seen/<library>@<major.minor>`; minor bump invalidates the record).
- `lib/deps.sh` (new): `deps_check_main` (entry point for `slopguard deps-check`), `deps_fetch` (sole network call, overridable via `SLOPGUARD_FETCH_CMD` for offline tests), `deps_version_cmp`, `deps_age_days`, `deps_verdict` (verdicts: `ok | minor-behind | major-behind | too-fresh | unknown`).
- `bin/slopguard`: two new subcommands — `note-docs` (reads hook JSON on stdin, records Context7 library lookup, never emits a decision) and `deps-check [--json] [<root>]` (sources `lib/deps.sh`, calls `deps_check_main`); both added to the `ensure_jq` guard list, the dispatch `case`, and `cmd_help`.
- `hooks/hooks.json`: new `PreToolUse` matcher `mcp__context7__.*` → `slopguard note-docs` (timeout 5 s). Absent Context7 server → matcher never fires; degradation is silent, never a `deny`.
- `profile.json` (session state): new field `.framework_versions` — map of framework tag → installed version string read from lockfiles; present only for stacks with a `context7` field; absent lockfile → key omitted, never `null`.
- `.claude-plugin/plugin.json` (`userConfig`): three new options — `require_docs_lookup` (boolean, default `true`); `dependency_freshness` (`off | warn | error`, default `"warn"`); `dependency_cooldown_days` (string, default `"3"`). Hooks receive these as `CLAUDE_PLUGIN_OPTION_REQUIRE_DOCS_LOOKUP`, `CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS`, `CLAUDE_PLUGIN_OPTION_DEPENDENCY_COOLDOWN_DAYS`.
- `docs/recommended-project-settings.json`: `mcpServers` snippet added for Context7 (`npx -y @upstash/context7-mcp`) with a `$comment` explaining that the plugin does not install the server itself and degrades silently when it is absent.
- Spec updated to v0.3 (2026-09-21):
  - §4.1: directory tree gains `lib/` subtree (`state.sh`, `detect.sh`, `config.sh`, `typosquat.sh`, `docs.sh`, `deps.sh`) and `rules/registries.json`.
  - §4.2: `plugin.json` manifest extended with `require_docs_lookup`, `dependency_freshness`, `dependency_cooldown_days`; env-var names documented.
  - §4.3: `hooks/hooks.json` gains `mcp__context7__.*` matcher; Uwagi extended with degradation note.
  - §4.4: dispatcher table gains `note-docs` and `deps-check [--json] [<root>]` rows.
  - §4.5: `docs-lookups.json` session-state file documented; `profile.json.framework_versions` documented.
  - §7.6 (new): `Dokumentacja frameworków przez Context7` — why hooks cannot call MCP, the observation mechanism, division-of-labour table with `rules/catalog.yaml` (including the conflict rule), `context7` field in `rules/stacks.json`, first-edit injection, cross-session memory.
  - §7.7 (new): `Świeżość zależności` — current ≠ floating distinction, 3-day cooldown rationale, `rules/registries.json` schema, `slopguard deps-check` verdict table and exit codes, Stop-gate wiring deferred to Etap 4.
  - §8.8: AP-AGENT-008 (library or framework API used without checking version docs in Context7) and AP-AGENT-009 (new dependency added without verifying it is the current stable version) added to always-on set; 15-line / 1500-character budget cap re-stated explicitly.
  - §11.3: Etap 1 gains Context7 trace and `deps-check`; Etap 4 gains Stop-gate wiring of `deps-check` and AP-AGENT-010 session-level check.
  - §12: decisions D17–D20 appended (observe-not-fetch for Context7; 3-day cooldown as `too-fresh`; `dependency_freshness` default `warn`; Context7 scope limited to frameworks and new dependencies).
- `docs/decisions.md`: D17–D20 appended in file's existing row format (2026-09-21).
- `rules/stacks.json` (new): single source of truth for stack tags — 17 tier-1 and 5 tier-2
  (`java`, `kotlin`, `csharp`, `ruby`, `rust`) entries with detection anchors, `requires`
  gating, `implies` expansion, file globs and skill routing.
- `lib/detect.sh`: rewritten data-driven over `rules/stacks.json`; adds `stacks_all`,
  `stack_known`, `stack_tier`; `SLOPGUARD_STACKS_JSON` overrides the data path.
- `lib/config.sh` (new): `.slopguard.json` per-project resolution — `config_resolve_stacks`
  sets `SG_STACKS`, `SG_STACKS_SOURCE`, `SG_STACKS_WARNINGS`. `stacks` replaces autodetection;
  `paths` declares tags per subtree verbatim for monorepos; a broken file falls back to
  autodetection with a warning, never to zero coverage.
- `hooks/session-start`: digest now names the stack source, flags tier-2 stacks as
  prevention + SAST only, and prints one line per warning; `profile.json` gains
  `stacks_source` and `stacks_warnings`.
- `hooks/pre-write`, `rules/policies/write.yaml`: `.slopguard.json` is an unconditionally
  protected file — editing it is `ask`, so the agent cannot silence a language layer.
- `tests/`: `config_test.sh` (new) plus tier-2, `requires`/`implies` and API cases in
  `detect_test.sh`; suite at 169 assertions.
- Spec updated to v0.2 (2026-09-17): tier-2 language support design, `rules/stacks.json` as
  single source of truth, and `.slopguard.json` per-project configuration documented.
- `docs/slop-guard-spec.md` §4.1: directory tree extended with `rules/stacks.json` (single
  source of truth for stack tags) and four tier-2 skill directories (`jvm-antipatterns`,
  `csharp-antipatterns`, `ruby-antipatterns`, `rust-antipatterns`).
- `docs/slop-guard-spec.md` §4.8 (new): `rules/stacks.json` schema documented — tier, anchors
  (OR-ed), requires (detection gate), implies, globs, skill; example covering Go (tier 1),
  Laravel (tier 1 with `requires`), Helm (with `implies`), Java (tier 2).
- `docs/slop-guard-spec.md` §4.9 (renumbered from §4.8): catalog `language` field extended
  to accept scalar or list; `AP-JVM-SEC-001` (JDBC string concatenation) added as example of
  shared JVM entry covering both Java and Kotlin.
- `docs/slop-guard-spec.md` §4.5: `profile.json` fields `stacks_source` and `stacks_warnings`
  documented.
- `docs/slop-guard-spec.md` §5.2 (new): tier-1 / tier-2 coverage table; `SessionStart` digest
  format showing tier warnings and unknown-stack notices.
- `docs/slop-guard-spec.md` §7.2C: `.slopguard.json` added to protected `tool_configs` list.
- `docs/slop-guard-spec.md` §7.5 (new): `.slopguard.json` per-project configuration — JSON
  rationale (D12), `stacks`/`paths` schema, monorepo example, full error table, fail-safe
  rationale, precedence chain, write-protection cross-reference.
- `docs/slop-guard-spec.md` §8.10 (new): planned tier-2 catalog sets (AP-JVM-*, AP-CS-*,
  AP-RB-*, AP-RS-*) at 8–12 rules each, security-first, MIT Opengrep rules only.
- `docs/slop-guard-spec.md` §11.3: Etap 0 gains Opengrep parser probe for tier-2 languages
  as entry condition; Etap 1 gains `rules/stacks.json`, data-driven `detect_stacks`, and
  `.slopguard.json` support; Etap 3 gains tier-2 Opengrep rules; Etap 5 gains tier-2 catalog
  entries and generated skills.
- `docs/slop-guard-spec.md` §12: decisions D12–D16 added (JSON over YAML for project config,
  `rules/stacks.json` as single source of truth, two-tier coverage model, C/C++ deferred,
  `osv-scanner` deferred to Stage 4).
- `docs/decisions.md`: D12–D16 appended in file's existing row format.
- `docs/ideas.md`: C/C++ deferred (D15) and `osv-scanner`-based SCA (D16 Stage 4 follow-up)
  recorded.

- Plugin skeleton: directory layout, manifest (`plugin.json`), empty hook manifest (`hooks.json`).
- Licence notices: `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md`.
- Design decisions recorded in `docs/decisions.md` (D1 bash+jq, D2 Opengrep, D10 GitHub Actions confirmed; D3–D9 taken at spec recommendation; D11 open, interim default postgres).
- Baseline configs created from spec §6 verbatim (exceptions noted): `phpstan.neon`, `psalm.xml`,
  `phpmd.xml`, `.golangci.yml`, `pyrightconfig.json`, `eslint.config.mjs`, `.sqlfluff`,
  `.squawk.toml`, `.checkov.yaml`, `.kube-linter.yaml`, `.hadolint.yaml`, `zizmor.yml`,
  `.gitleaks.toml`. Exceptions: `ruff.toml` (spec comments in Polish — translated to English per
  plugin language rule); `.tflint.hcl` (spec placeholder `X.Y.Z` for AWS plugin version —
  `plugin "aws"` block commented out pending tflint pin in `tools.lock.json`);
  `eslint.security-overlay.mjs` (spec §6.4 describes role but gives no verbatim content — derived
  from the JS/TS common security block of `eslint.config.mjs`; `extends: [js.configs.recommended]`
  omitted since the overlay is a second pass, not a replacement config).
- `slopguard doctor --install` now installs every analyzer required by the section 9.3
  config gate, plus jq and ShellCheck. Binary and PHAR releases use per-platform SHA-256
  pins; Python and Node dependencies use hash-pinned lockfiles.
- `scripts/validate-configs` is part of the Make and CI gates and fails when any required
  config is skipped. The tflint baseline now pins AWS ruleset 0.48.0. Opengrep validation
  starts when Stage 3 adds the first own rule files.
- Fixture directories created: `tests/fixtures/{php,python,ts,terraform,docker,kubernetes,ci}/good/`.
  Each contains a minimal valid file sufficient for the §9.3 validation command to run.
  `ci/good/workflow.yml` uses pinned action hash and `persist-credentials: false`.
- Stage 1 hook runtime: session stack/profile detection, pre-read secret paths, pre-bash
  supply-chain policy with quote-aware compound-command parsing, and pre-write secret,
  suppression, protected-config, and first-edit context checks.
- Headless queue runs now fail closed for interactive `ask` decisions while advisory mode
  reports non-secret policy findings as context. Guard ownership no longer overlaps `sdlc`.
- Hook-contract coverage now includes macOS-compatible hashing and shell behavior,
  NotebookEdit payloads, stale-session resume, enforcement modes, and plugin/marketplace
  version consistency.
