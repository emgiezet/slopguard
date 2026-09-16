# tools.lock.json — scope and maintenance rules

## What is pinned here and why

Stage 0 pins every analyzer needed by the spec section 9.3 config gate, plus
`jq` and `shellcheck`: Betterleaks, Checkov, ESLint, golangci-lint, hadolint,
kube-linter, Opengrep, PHPStan, Psalm, Ruff, tflint, and zizmor.

`jq` is bootstrapped before the dispatcher parses JSON. This prevents a missing
system package from disabling policy hooks. `shellcheck` validates the plugin's
own shell code.

Binary and PHAR releases carry a hash for each supported platform. Ruff and
Checkov share a hash-pinned Python lock. The ESLint stack uses an npm lockfile
and installs with lifecycle scripts disabled. tflint also pins its AWS ruleset
in the baseline config.

## Schema

See spec §9.2 for the canonical schema. Each binary tool entry carries:

- `version` — the exact release tag (without a leading `v`).
- `assets.<platform>.url` — the release asset URL. No mutable tags; the URL
  must point at an immutable release (by tag and filename).
- `assets.<platform>.sha256` — the SHA-256 of the downloaded asset, computed
  from a local download, not copied from an external source. Verified by
  `install_tool` before extraction.
- `bin` — the name of the executable inside the extracted/copied directory.

## Version bump procedure

A version bump is a pull request that:

1. Updates `version` and all `assets` entries in this file.
2. Recomputes every `sha256` by downloading the new assets and running
   `sha256sum` (or `shasum -a 256`) locally.
3. Keeps `plugins/slop-guard/tests/run-tests` green after the bump.

Automated tooling (Renovate, Dependabot) may open the PR but **must not
merge it automatically** — a human reviews the hashes.

## 7-day publication rule

Nothing is pinned within 7 days of its release publication date. The window
allows detection of a malicious or compromised release before it enters the
lockfile (see D5 in `docs/decisions.md` for the Trivy/KICS incident that
motivated this rule).

Check the publication date with:

```bash
curl -sS https://api.github.com/repos/<owner>/<repo>/releases/tags/<tag> \
    | jq -r .published_at
```

If the newest release is younger than 7 days, pin the one before it and record
this in the PR description.
