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
