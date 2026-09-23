# Slop Guard — Design Decisions

Date confirmed: **2026-09-16**

---

## Blocking Decisions (confirmed before Stage 1)

| # | Decision | Answer | Date | Consequence |
|---|---|---|---|---|
| D1 | Dispatcher language | **bash + `jq`** | 2026-09-16 | No compiled artefact, no cross-compilation, no release matrix. `jq` is the only added pinned dependency (Task 0.2) — `flock` is not available on macOS and is not used; file locks are implemented with `mkdir`. Every JSON response is built with `jq -n --arg`. Tests are bash assertions, not `go test`. `shellcheck -S warning` is the CI gate, shared with `plugins/sdlc/bin/aisdlc`. Windows support is a wrapper problem deferred to Stage 6 and recorded as a known limitation. |
| D2 | SAST engine | **Opengrep** (`sast_engine=semgrep\|none` still works) | 2026-09-16 | Own rules are kept in the syntax both Opengrep and Semgrep CE parse. Taint-mode rules are marked in the catalogue so a `semgrep` fallback degrades visibly, not silently. |
| D10 | Target CI system | **GitHub Actions** | 2026-09-16 | Stage 2 implements `actionlint` + `zizmor` with `unpinned-uses: hash-pin`. The GitLab Opengrep rule set (§6.9) moves behind Stage 2, and AP-CI-006 ships in Stage 3 or later. |

### Why Opengrep rather than Semgrep CE

The rules that need dataflow tracking are the ones no other tool in the matrix covers. PHP has Psalm taint and Go has `gosec`; Python, TypeScript and Node have nothing free that tracks `req.body` to a sink. AP-NODE-SEC-001, AP-PY-SEC-001 and AP-TS-SEC-004 are precisely those, and Opengrep keeps intra-file taint in the open-source engine while Semgrep moved it behind the paid tier.

The rule format and JSON/SARIF output are identical, so `sast_engine` stays a one-word switch rather than a rewrite. Neither engine changes the licence problem — Semgrep Registry rules cannot be shipped either way, so the plugin writes its own rules regardless. Opengrep costs nothing extra here.

The risk is maintenance, not capability: the fork is young and small. Mitigations: pin it by sha256 like every other binary, and keep every own rule inside the syntax Semgrep CE also parses, verified by running `scripts/validate-configs` with `sast_engine=semgrep`.

---

## Non-Blocking Decisions (taken at the spec's recommendation)

| # | Decision | Answer | Consequence |
|---|---|---|---|
| D3 | Default enforcement mode | **balanced** | `strict` for repos with high requirements (payment/personal-data modules). `advisory` available for low-friction onboarding. |
| D4 | Stop gate blocking behaviour | **Blocks on blockers only; at most 2 iterations** | The Stop handler checks `stop_hook_active` and gives up after 2 failed iterations, leaving a summary for the user. Only `error`-severity findings block; warnings do not. |
| D5 | Trivy / KICS | **Off by default** | On 19 March 2026 an attacker published a malicious Trivy v0.69.4 that overwrote 76 of 77 `aquasecurity/trivy-action` tags and all 7 `aquasecurity/setup-trivy` tags with credential-stealing code; KICS was hit in the same campaign (§5.1). A plugin running on developer machines with access to secrets must not fetch these tools unverified. Checkov + tflint + kube-linter cover the same IaC scope. If re-enabled via project config, Trivy or KICS must be pinned by sha256 to a version published after the incident. |
| D6 | JS/TS linter | **ESLint + typescript-eslint** | Type-aware rules (`no-floating-promises`, etc.) are enabled. Biome/Oxlint as a fast tier-F option is recorded in `docs/ideas.md` for consideration if performance becomes a problem. |
| D7 | Python type checker | **Project's own type checker; Pyright (standard mode) as fallback** | If the project ships a `pyrightconfig.json` or `pyproject.toml [tool.pyright]`, that configuration is used. Otherwise Pyright runs in standard mode. |
| D8 | Network in fast path | **`allow_network=false` by default** | SCA runs in CI rather than in the plugin until a local vulnerability-database mirror is available. Users may set `allow_network=true` to enable SCA in the Stop gate. |
| D9 | Overlap with `security-guidance` / Claude Security | **No LLM-review duplication** | If `security-guidance` is enabled, `/slop-guard:secure-review` defers to it instead of launching an independent LLM review (§3.5). |

---

## Open Decisions

| # | Decision | Status | Interim default | Notes |
|---|---|---|---|---|
| D11 | Default SQL dialect | **Open** (blocks nothing before Stage 2) | **postgres** | MySQL has no equivalent of `squawk`, which means more custom rules and a larger skill. Until this is answered, `squawk` runs only on PostgreSQL migrations. The answer determines the scope of Stage 2's SQL tooling. |

---

## Implementation Policy Notes

### Why `hooks/hooks.json` stays empty until Stage 1

A `hooks.json` entry that points at a subcommand which does not yet exist fails open: Claude
Code executes nothing and the defect is invisible. Each hook binding therefore lands in the
same commit as its handler. Hooks are wired in Stage 1, one subcommand at a time.

### Guard ownership and unattended prompts

The `sdlc` guard exclusively owns force pushes, `--no-verify`, destructive `rm -rf`
outside the worktree, and deleted or skipped tests at turn end. Slop Guard owns
secrets, suppressions, protected quality configuration, dependency supply-chain
checks, and lint findings. Keeping one owner per action avoids contradictory blocks.

Queued phases export `AISDLC_HEADLESS=1` and run with `bypassPermissions`, so nobody
can answer an `ask` decision. In that environment every Slop Guard `ask` becomes a
`deny` with the original reason plus “no human in this session”; it never silently
allows the action.

---

## Decisions Confirmed 2026-09-17

### Blocking

| # | Decision | Answer | Date | Consequence |
|---|---|---|---|---|
| D13 | Single source of truth for stack tags | **`rules/stacks.json`** | 2026-09-17 | `lib/detect.sh`, `.slopguard.json` validation, skill routing and Opengrep rule selection all read this one file. Path overridable via `SLOPGUARD_STACKS_JSON` so tests can point elsewhere. Required before Stage 1: without it `detect_stacks` cannot add tier-2 languages without duplicating tag lists. |

### Non-Blocking

| # | Decision | Answer | Date | Consequence |
|---|---|---|---|---|
| D12 | Project config file format | **JSON** (`.slopguard.json`), not YAML | 2026-09-17 | D1 pins bash + `jq`; `yq` is not in `tools.lock.json`. Adding a parser dependency for one user-authored file is disproportionate. Plugin's own policy files (e.g. `bash.yaml`) are read by `awk`/`sed` because their format is plugin-controlled; a user-authored file needs a real parser, and `jq` satisfies that directly. |
| D14 | Two-tier coverage model | **Tier 1** (PHP, Go, Python, TS/Node, IaC, CI): native linters + type/dataflow analysis. **Tier 2** (JVM, C#, Ruby, Rust): prevention skill + Opengrep SAST only | 2026-09-17 | Tier 2 selected where no type-analysis-capable tool is available without a compiler in the matrix. `SessionStart` prints the tier so silence is not mistaken for cleanliness. `maintainability`/`performance` coverage is thin on tier 2. |
| D15 | C/C++ support | **Deferred.** Meaningful C/C++ static analysis requires `compile_commands.json` (generated by cmake/bear) — a tool absent from the plugin matrix. Purely syntactic rules would give false confidence due to user-defined types and macros. | 2026-09-17 | Recorded in `docs/ideas.md` as future work requiring a separate project (compile-commands-aware toolchain). |
| D16 | `osv-scanner` | **Deferred to Stage 4.** `hooks/hooks.json` currently has only `SessionStart` and `PreToolUse`; the Stop gate that would call it does not exist yet. Pinning it now would add an uncalled dependency to `tools.lock.json`. | 2026-09-17 | `osv-scanner` lands in `tools.lock.json` in the same commit as the Stop handler in Stage 4. Recorded in `docs/ideas.md` as the Stage 4 SCA follow-up. |

---

## Decisions Confirmed 2026-09-21

### Non-Blocking

| # | Decision | Answer | Date | Consequence |
|---|---|---|---|---|
| D17 | Context7 integration mechanism | **Observe, don't fetch.** A hook is a bash process; MCP tools belong to the agent layer. `PreToolUse` with matcher `mcp__context7__.*` captures Context7 calls already made by the agent and writes the library to `docs-lookups.json`. No Context7 server → matcher never fires; plugin degrades silently. **Absence of Context7 never produces `deny`.** | 2026-09-21 | `lib/docs.sh` implements `docs_note`/`docs_seen`/`docs_remember`/`docs_recall`. The hook is a passive observer only. |
| D18 | Cooldown window for new package releases | **3 days, verdict `too-fresh`** (not `deny`). Recommending a version published hours ago walks the agent into the supply-chain window that `lib/typosquat.sh` and the `popular-packages` lists exist to avoid. `too-fresh` is `ask`, not a hard block, and takes priority over `major-behind`. | 2026-09-21 | Configurable via `dependency_cooldown_days` (default `"3"`). `deps_verdict` in `lib/deps.sh` implements the comparison. |
| D19 | Default for `dependency_freshness` | **`warn`**, not `error`. An `error` default on a first run against a legacy repo would produce a wall of findings and prompt the user to disable the plugin — defeating the purpose entirely. `warn` notifies without blocking; teams can escalate to `error` via `userConfig` or `.slopguard.json`. | 2026-09-21 | Mirrors the existing `advisory`/`balanced`/`strict` philosophy: start non-blocking, tighten selectively. |
| D20 | Scope of Context7 documentation requirement | **Limited to framework tags and newly added dependencies.** Enforcing per-library for every repo library would cost a dozen MCP calls per turn. The value of Context7 is version-specific framework conventions (`laravel`, `symfony`, `doctrine`, `react`, `vite`, `express`, `terraform`) and docs for a freshly added package. | 2026-09-21 | Only tags with a `context7` field in `rules/stacks.json` trigger the first-edit injection. `require_docs_lookup=false` suppresses all injection globally. |
| D21 | Exit behaviour of `validate-configs` under partial toolchain | **Lenient by default; `--strict` in CI.** Skipped tools (tool absent on this machine) are not validation failures in the default mode. CI passes `--strict` via `CONFIG_STRICT := $(if $(CI),--strict,)` in the Makefile; GitHub Actions sets `CI=true` automatically. | 2026-09-23 | The previous behaviour exited 1 on any skip, making `make validate` unpassable on a developer machine missing any of the 11 linters. Because `validate` lists `validate-slopguard` as a prerequisite, the entire `plugins/sdlc` half of `make validate` never executed locally — silently hiding failures. |
| D22 | Grok / multi-host normalization strategy | **Normalize camelCase → snake_case at the `hook_input` boundary; emit the host-correct envelope in `hook_deny`/`hook_ask`/`hook_allow`/`hook_context`/`hook_message`.** | 2026-09-23 | The alternative — adding a per-host fallback in every policy script (`hooks/pre-bash`, `hooks/pre-write`, `hooks/pre-read`) — would require each script to know the active runtime and duplicate the envelope logic. By normalizing once at the boundary, all policy scripts remain host-agnostic: they read snake_case fields and call the same helpers regardless of host. Runtime detection (`_SLOPGUARD_RUNTIME`) uses a compound condition rather than `GROK_PLUGIN_ROOT` alone, because a stale inherited variable in a Claude session would otherwise cause every deny to be answered in the Grok envelope, which Claude ignores — making every deny a silent allow. |
| D23 | Project-scoped extension mechanism | **`.slopguard/` directory with two classes: mapping overrides and tool descriptors.** No user/machine scope (`~/.config`). Extensions travel with the repo; configuration that does not travel makes developer results differ from CI, which is the failure class this plugin exists to catch. | 2026-09-23 | `lib/ext.sh` (`ext_load_mapping`, `ext_tools`, `ext_validate`, `ext_override_counts`, `ext_dir`). Trust boundary: `run.args` is an argv array (no shell); `parse.jq` is a jq expression (no script); binary resolution requires a project path or a PATH sha256 match; the plugin never installs a descriptor's tool. A descriptor whose name collides with a pinned tool is refused. All files under `.slopguard/**` are `ask`-protected by `pre-write` (§7.2C). Severity downgrades are allowed and counted; silent downgrading is AP-AGENT-002. |
