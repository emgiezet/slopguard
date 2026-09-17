# Changelog

All notable changes to Slop Guard will be documented in this file.

## Unreleased
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
