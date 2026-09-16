# Changelog

All notable changes to Slop Guard will be documented in this file.

## Unreleased

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
