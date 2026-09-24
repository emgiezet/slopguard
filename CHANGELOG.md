# Changelog

All notable changes to Slop Guard will be documented in this file.

## Unreleased
- **jscpd wired as duplication detector; dead-code rules for ruff and ESLint; deslop editing skill** (2026-09-24)
  - `tools/tools.lock.json`: jscpd 5.3.2 pinned for four platforms (linux-amd64, linux-arm64, darwin-amd64, darwin-arm64), sha256-verified, MIT; `https://github.com/kucherenko/jscpd`.
  - `lib/dispatch.sh`: `_dispatch_run_jscpd` — runs jscpd directory-scoped against the directory of the changed file; routed from `_dispatch_medium_tools_for_file` for `py js jsx mjs cjs ts tsx mts cts go php java kt kts cs rb rs`, never at the fast tier. Findings emitted via `_dispatch_filter_emit` (diff filter only), bypassing the security overlay; `tool_config_mode = skip` still honoured.
  - `rules/mapping/jscpd.yaml`: single rule `duplicate-block` → `AP-SLOP-DUP-001`, severity `warn`, category `maintainability`. Bucket id, no catalogue page — same pattern as `AP-CI-LINT-000`, `AP-DOCKER-LINT-000`.
  - `configs/baseline/.jscpd.json`: `minLines: 5`, `minTokens: 50`, JSON reporter, `gitignore: true`, ignore list for vendored and generated trees. Known to `tool_config_path` and `_adopt_dest`.
  - `configs/baseline/ruff.toml`: `ARG`, `ERA001`, `RET505`, `TRY300`, `TRY400` added to the selected rule set on top of the existing `F`, `SIM`, `PL`, `C90` — dead code, commented-out code, redundant control-flow, and exception-handling patterns found disproportionately in LLM-generated code (arXiv:2508.14727: dead/unused code at 34.8–42.7% of all smells). New bucket id `AP-PY-LINT-000` added to `rules/mapping/ruff.yaml`.
  - `configs/baseline/eslint.config.mjs`: `no-unused-vars`, `no-unreachable`, `no-dupe-else-if`, `no-constant-condition`, `no-empty`, `no-useless-catch`, `no-useless-return` added as `error`; `complexity` (max 15), `max-lines-per-function` (max 80), `max-depth` (5), `max-params` (5) added as `warn`. New bucket id `AP-TS-LINT-000` added to `rules/mapping/eslint.yaml`.
  - `skills/deslop/SKILL.md` (new): `/slop-guard:deslop <path>` — user-invocable skill; argument is a file or directory; `--dry-run` previews without writing; `--tests <cmd>` unlocks structural refactoring (the agent must run the command and confirm it passes before finishing). Without a test command the agent performs pure deletions only and declines behaviour-bearing restructuring.
  - `agents/deslop.md` (new): editing subagent behind the deslop skill. Unlike `agents/security-reviewer.md`, Write and Edit are permitted; the safety boundary is the `--tests` requirement for structural changes, not a tool restriction.
  - `docs/research/ai-slop-code-smells.md`, `docs/research/code-smell-tooling.md`, `docs/research/skill-and-command-conventions.md`, `docs/research/tool-integration-checklist.md` (new): supporting research on AI code-smell frequency, tooling landscape, and skill conventions.
  - **Why duplication and not complexity as the primary AI-slop discriminator.** GitClear 2025 analysed 211M changed lines and found ≥5-line duplicate block frequency rose 8× in 2024 — the first year copy-paste exceeded moved code. GitClear 2026 reports 73.0 duplicate blocks per million lines; moved code fell to 3.8%, copy-paste reached 15.7%. arXiv:2508.21634 (ISSRE 2025, 500k samples) found no reliable difference in cyclomatic complexity between AI-generated and human-written code: the structural metric does not separate the two populations. Complexity rules (`complexity`, `max-lines-per-function`) are therefore included only as supporting `warn` signals, not as the primary detection target.
  - **Why the medium tier and directory scope rather than fast and per-file.** Duplication is inherently cross-file: a block in file A is a duplicate only relative to blocks in other files. A per-file fast-tier call would either miss cross-file duplication entirely or re-index the entire directory on every write, defeating the debounce. Running jscpd at the medium tier against the directory of the changed file keeps the indexing cost bounded (one pass after the edit batch settles) and the result correct.
  - **Why duplication findings bypass the security overlay.** The security overlay (`config_source=overlay`) exists to avoid imposing style opinions from a baseline config on a repository that never opted in — it drops every finding whose mapped category is not `security`. Duplicate-block findings have `category: maintainability`; in the default configuration every jscpd finding would be dropped, making the tool dead on arrival. Emitting via `_dispatch_filter_emit` bypasses the overlay category filter while still honouring `tool_config_mode = skip`. The boundary: the overlay suppresses style-rule findings whose values are opinions; a duplicate-block threshold (`minLines: 5`, `minTokens: 50`) is a measurement count with no style opinion embedded.
  - **Why radon, lizard, vulture and knip were rejected.** radon and lizard measure cyclomatic and cognitive complexity; arXiv:2508.21634 shows complexity does not reliably separate AI-written from human-written code, so their findings would not correlate with slop and would produce noise. vulture and knip detect dead/unused symbols but require full project-environment resolution (they need the complete import graph to avoid false positives on re-exported symbols); ruff (`ERA001`, `ARG`, `RET505`) and ESLint (`no-unused-vars`, `no-unreachable`) cover the same dead-code category with lower friction and no resolution step. None of the four warranted a pin in `tools.lock.json`.

- **Tool relevance scoped to the project's stacks; mypy and pylint via project-local descriptors** (2026-09-24)
  - `rules/stacks.json`: every stack entry gains a `tools` array naming the pinned tools that stack can use (e.g. `python` → `ruff`, `opengrep`; `github-actions` → `zizmor`, `checkov`). Framework stacks that add no tool of their own carry `[]` and inherit through `requires`/`implies`.
  - `lib/detect.sh`: `SLOPGUARD_CORE_TOOLS` (`betterleaks jq shellcheck`) plus `stack_tools <tag>` and `tools_for_stacks <stacks>`. Core tools are stack-independent: jq parses every hook's input, secret scanning reads the raw diff, and shell scripts carry no stack anchor.
  - `hooks/session-start`: resolves and probes only the relevant tools. Irrelevant ones are inventoried with `source: not-applicable` and a new `relevant: false` field in `profile.json`, and never reach the missing-tools report. Banner reworded to `missing tools for this project:`. The overlay-config count now counts relevant tools only.
  - `bin/slopguard doctor`: scoped to the detected stacks by default and prints a `scope:` line; `--all` restores the full inventory. `doctor --install` therefore installs what the project can use, not all fourteen pins.
  - `configs/baseline/descriptors/{mypy,pylint}.yaml` (new): project-local tool descriptors adopted with `slopguard adopt-config mypy|pylint` into `.slopguard/tools/`. Resolution is `.venv/bin`, `venv/bin`, `.tox/py/bin` only — both tools resolve imports through the project's interpreter, so a plugin-installed copy would report phantom errors. The plugin pins and installs nothing for them.
  - `rules/mapping/{mypy,pylint}.yaml` (new): pylint symbols that name a catalog anti-pattern carry its ap_id (`bare-except`/`broad-exception-caught` → AP-PY-MAINT-001, `dangerous-default-value` → AP-PY-MAINT-002, `eval-used`/`exec-used` → AP-PY-SEC-007); everything else takes a bucket id (`AP-PY-TYPE-000`, `AP-PY-LINT-000`).
  - `hooks/post-write`: a `Details: skills …/reference/<id>.md` line is emitted only when that reference file exists — bucket ids have no reference page, and the pre-existing `AP-DOCKER-LINT-000` / `AP-PHP-MAINT-000` / `AP-CI-LINT-000` buckets had the same dangling-link behaviour.
  - `Makefile`: three new `stacks.json` gates — every entry declares a `tools` array, every named tool is pinned in `tools.lock.json`, and every pinned tool is reachable from some stack or the core set (a tool reachable from neither would never run).
  - **Why an empty `ap_id` is not allowed in a mapping.** `_dispatch_run_one_ext_tool` reads the mapping row as `@tsv` into `IFS=$'\t' read -r ap_id severity category cwe`. Tab is IFS whitespace, so a leading empty field collapses and severity lands in `ap_id` — findings silently report at the wrong severity. Bucket ids are load-bearing, which is why the shipped hadolint, phpstan, and zizmor mappings already use them.
  - **Why pylint runs with `--exit-zero`.** Pylint encodes its result as a bitmask (1 fatal, 2 error, 4 warning, 8 refactor, 16 convention) and the descriptor runner discards output from any exit code other than 0 or 1, so a warning-only run would vanish. Severity comes from `rules/mapping/pylint.yaml`, never from pylint's exit status; this is an output-plumbing fix, not a lowered threshold.
- **Integration test suite against real tool binaries (D30)** (2026-09-24)
  - `tests/tool-integration` (new): runner that globs `tests/integration/*.sh` in sorted order, counts `ok`/`bad`/`skip`, prints a summary, and exits non-zero on any failure. A skipped tool is not a failure — a developer without the full toolchain still gets a useful run.
  - `tests/integration/fast.sh`, `tests/integration/medium.sh`, `tests/integration/stop.sh` (new): per-tier cases that invoke each wired linter's own `bad`/`good` fixture through `bin/slopguard post-write --tier=<tier>` and assert the finding carries the correct `AP-*` id.
  - `Makefile`: `tool-integration` target added — guarded by `test -x` so the target is honest when the file is absent; not wired to `validate`; CI runs it after `slopguard doctor --install`.
  - `.github/workflows/validate.yml`: "Tool integration tests (real binaries)" step added to the `validate` job immediately after `make validate`, reusing the same `CLAUDE_PLUGIN_DATA` env. The `validate` job installs the full pinned toolchain via `slopguard doctor --install`; no tool is skipped in CI.
  - `docs/slop-guard-spec.md` §11.1: test class 7 (integration with real binaries) added — rationale, the two concrete false-green cases (PHPStan `.files[].errors` vs `.messages`; ruff `.row` vs `location.row`), and the CI/developer-machine split.
  - `docs/decisions.md`: D30 recorded — the defect class, the design (CI-only, skip-per-tool on dev machines), and the consequence (parser that misreads its tool fails the build).
  - **Why unit stubs are insufficient (D30).** A stub is written by the author of the parser; if the author has a wrong mental model of the tool's JSON format, both the parser and the stub share that model. The integration suite is the only place where the real binary's actual output meets the actual parser.

- **Security overlay as default baseline fallback (`config_source`)** (2026-09-23)
  - `plugin.json` (both manifests): `config_source` added to `userConfig` adjacent to `tool_source`; type string, default `"overlay"`, description `"overlay | full | project-only"`. Hook env: `CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE`.
  - `docs/slop-guard-spec.md` §2 Z1: third bullet rewritten — baseline configs now behave as a security overlay by default; `config_source` knob documented with all three values and the rationale (repositories that never adopted our style rules should not receive them; security is what the guard is installed for; unknown rules are not treated as security in overlay mode).
  - `docs/slop-guard-spec.md` §4.2: `config_source` added to the manifest example; env-var list updated to include `CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE`.
  - `docs/slop-guard-spec.md` §6: heading and intro reframed — configs in `configs/baseline/` are examples, adopted via `slopguard adopt-config <tool>` or ignored; the security overlay applies until adoption; adopted configs are write-protected.
  - `docs/slop-guard-spec.md` §9.1: config source table added as a sub-section — full interaction matrix of `tool_source` × `config_source` × project binary / config presence; `tool_config_mode` return values documented.
  - `plugins/slop-guard/configs/baseline/README.md` (new): what the directory is (examples, not defaults), what happens if ignored (security overlay), how to adopt, write-protection after adoption, `config_source` knob table.
  - `README.md`: short paragraph added to the Slop Guard section — with your own linter config the plugin reports everything; without one it reports only security findings; `slopguard adopt-config` command shown.
  - `plugins/slop-guard/docs/decisions.md`: D29 added — security overlay as default; rejected alternative `project-only` (would silence SQL-injection in repos least likely to have a linter configured); rejected `full` as implicit previous behaviour (causes first-session style noise that prompts users to disable the guard).
  - **Why `project-only` was rejected (D29).** Skipping a tool when no project config exists silences SQL-injection and secret-handling detections in exactly the repositories least likely to have a linter configured — the ones that need the guard most. The overlay is the least-surprise middle ground: security always, style only when the project has opted in.

- **Etap 6 — Hardening and distribution (partial)** (2026-09-23)
  - `docs/slop-guard-spec.md`: §11.2 updated — eval cases exist as specifications; the 0.8 threshold is the target, not a measured result; maintainer command documented. §11.3 Etap 3–6: stage records added for what shipped and what did not; every unwired tool named as Etap 0 work.
  - `plugins/slop-guard/docs/decisions.md`: D25–D28 added (unwired tools policy; Stop gate cap; eval threshold status; Windows launcher deferred).
  - `plugins/slop-guard/docs/ideas.md`: Windows launcher blocker recorded with specific steps needed; SCA tool pinning priority order; `tsc` pin options.
  - `README.md`: Slop Guard section extended with detection tiers (fast/medium/slow — what each runs and when), Stop gate enforcement modes and loop-protection cap, prevention skills table.
  - `plugins/slop-guard/docs/recommended-project-settings.json`: `$comment_stop_gate` added — Stop gate is a plugin option, not a `settings.json` key; guidance for strict teams and `stop_gate: false` opt-out.
  - **Windows launcher blocked (D28).** `hooks/hooks.json` references `bin/slopguard` in exec-form; `bin/slopguard` is a bash script. A real Windows batch companion (`bin/slopguard.cmd`) is required but owned by MediumTier. The sdlc `run-hook.cmd` is itself a bash script and does not transfer. Windows unsupported in 0.1.0; deferred to MediumTier for the next milestone.
  - **Why unpinned tools were left out (D25).** Pyright, `tsc`, govulncheck, `composer audit`, `npm audit`, pip-audit, and osv-scanner are absent from `tools.lock.json`. Wiring a call to an arbitrary PATH binary — not pinned by URL + sha256 — reintroduces exactly the supply-chain risk the tool-pinning policy exists to prevent. The dispatcher skips each missing tool with a `slopguard: <tool> unavailable` note (Z6 fail-open); the gap is visible in `slopguard doctor`. The fix is an Etap 0 PR per tool, not a runtime shim.
- **Etap 5 — Prevention: catalog, generated skills, security subagent** (2026-09-23)
  - `rules/catalog.yaml` (new): full anti-pattern seed from spec §8 — tier-1 stacks (PHP, Go, Python, TS/React, Node, SQL, IaC, CI, agent-discipline) and tier-2 stacks (JVM, C#, Ruby, Rust) for languages that passed the Etap 0 Opengrep probe. Every tier-1 entry with a `detect` field has a `bad`/`good` fixture pair.
  - `scripts/gen-skills` (new): reads `rules/catalog.yaml`, emits `skills/*/SKILL.md` capped at 150 lines / 3000 tokens; aborts with a non-zero exit on overflow rather than truncating silently. Generates `reference/<ID>.md` per entry with `prevent_in_skill: true`.
  - Tier-1 skills generated: `php-antipatterns`, `go-antipatterns`, `python-antipatterns`, `ts-react-antipatterns`, `node-antipatterns`, `sql-antipatterns`, `iac-antipatterns`; each with `paths` frontmatter and `reference/` directory.
  - Tier-2 skills generated (per languages passing Etap 0 probe): `jvm-antipatterns`, `csharp-antipatterns`, `ruby-antipatterns`, `rust-antipatterns`.
  - Skill `agent-discipline` (no `paths` — always available): AP-AGENT-001–AP-AGENT-010, injected by `session-start` within the 15-line / 1500-character budget.
  - `agents/security-reviewer.md` (new): read-only subagent with `disallowedTools: Write, Edit`; invoked by `/slop-guard:secure-review` (`context: fork`).
  - **Why eval threshold is unverified (D27).** `claude plugin eval` requires a live API key and incurs model-call costs. The eight eval cases define prompts, graders, and scaffold scripts; the 0.8 threshold is the stated gate for 1.0 release. Running them is a pre-release step documented in §11.2, not an offline CI check.
- **Etap 4 — Stop gate** (2026-09-23)
  - `lib/stop.sh` (new): `stop_main` — runs slow checks on files changed in the session, enforces loop protection (max 2 iterations via `stop-iterations` session counter), emits final-turn report (unresolved blockers, added suppressions, lines changed outside finding hunks).
  - `hooks/hooks.json`: `Stop` entry added — calls `slopguard stop-gate`, timeout 600 s. `hooks/hooks.json` also gains the `PostToolUse` medium-tier entry with `asyncRewake: true` (Etap 3, same commit batch).
  - `bin/slopguard`: `stop-gate` subcommand added (sources `lib/stop.sh`, calls `stop_main`).
  - Wired tools (all in `tools.lock.json`): **Psalm taint** (`--taint-analysis --output-format=json`) — PHP dataflow; **Checkov** (directory-level scan of changed IaC/Docker/CI dirs); **Betterleaks** (full session-diff secret scan).
  - `slopguard deps-check` wired into Stop gate — runs when any dependency manifest (composer.lock, package-lock.json, go.sum, Pipfile.lock, Cargo.lock) changed in the session; verdicts `too-fresh` and `major-behind` reported per §7.7.
  - AP-AGENT-010 session check: at `require_docs_lookup=true`, framework files edited without a recorded Context7 lookup produce a `warn` in the final report — never a `deny`.
  - `tests/stop_test.sh` (new): assertions covering `stop_hook_active` short-circuit, iteration cap, advisory/balanced/strict modes, deps-check wiring.
  - **Why SCA tools are absent (D25).** govulncheck, `composer audit`, `npm audit`, pip-audit, and osv-scanner are not in `tools.lock.json`. The Stop gate logs `slopguard: <tool> unavailable` and passes through (Z6). See `docs/ideas.md` for the pinning priority order.
- **Etap 3 — Medium-tier detection (asyncRewake)** (2026-09-23)
  - `lib/dispatch.sh`: `dispatch_medium` function added — debounces a batch of edits by 3 s, routes changed files to medium-tier tools by stack, applies per-tool timeout, exits 2 with stderr only when new findings meet the threshold (triggering asyncRewake back to the agent).
  - `hooks/hooks.json`: second `PostToolUse` entry added — `asyncRewake: true`, no platform timeout (dispatcher manages time internally per §3.2).
  - `bin/slopguard`: `post-write --tier=medium` delegates to `dispatch_medium`.
  - Wired tools (all in `tools.lock.json`): **PHPStan** (level 8; `--level=max` for new untracked files) — PHP; **golangci-lint** (`--new-from-rev` restricts findings to changed packages) — Go; **ESLint with type-info** (eslint-stack + tsconfig path) — TS/JS; **tflint** (AWS ruleset) — Terraform; **Checkov** (file-level) — IaC/Docker/CI; **Opengrep** (own rules `rules/opengrep/`, same `--config` invocation for tier 1 and tier 2).
  - `rules/opengrep/`: own MIT SAST rules — one file per language, each validated by `opengrep --validate` and tested by `opengrep --test`. Tier-2 rules (AP-JVM-*, AP-CS-*, AP-RB-*, AP-RS-*) included for languages that passed the Etap 0 Opengrep parser probe.
  - `rules/mapping/{phpstan,golangci,opengrep}.yaml`: rule-id → AP-id, severity, category, CWE mappings for medium-tier tools.
  - `tests/medium_test.sh` (new): assertions covering debounce logic, per-tool routing, asyncRewake threshold, fail-open on timeout/missing binary, end-to-end §4.7 format.
  - **Why Pyright is absent (D25).** Pyright is the planned Python type-checker fallback (D7) but is not in `tools.lock.json`. An Etap 0 PR adding it with URL + sha256 per platform is the prerequisite. Until then the medium dispatcher logs `slopguard: pyright unavailable` and passes through.
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
- omp host support: `extensions/omp.mjs` (new) is a plain ESM adapter that translates omp `tool_call` events into the existing bash policy subcommands (`slopguard pre-bash`, `pre-read`, `pre-write`) and handles `session_start` by calling `slopguard session-start` and posting its stdout via `pi.sendMessage` so the AP-AGENT rules reach the model. Zero policy logic lives in the adapter — every decision comes from `bin/slopguard`. `package.json` (new) declares the omp extension entry point (`omp.extensions: ["./extensions/omp.mjs"]`) at version 0.1.0 matching `plugin.json`. The adapter fails open on subprocess timeout (5 s), spawn error, or unparseable output, and logs through `pi.logger` so a broken adapter never bricks the agent. `AISDLC_HEADLESS=1` is injected when `ctx.hasUI` is false, preserving the existing headless fail-closed contract for `ask` decisions.
- `tests/omp_adapter_test.mjs` (new) + `tests/omp_adapter_test.sh` (new): offline test suite for the omp adapter; runs under `node --test`; tests real `bin/slopguard` for policy round-trips (curl|sh block, benign allow, credential write block, .env read block with selector stripping, headless ask block) and stub runners for failure modes (unparseable output, missing binary, unknown tool spawns no subprocess).
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
