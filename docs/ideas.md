# Out-of-Spec Ideas

This file is the landing place for ideas that go beyond the current spec (§0.4).
Record an idea here rather than implementing it. Ideas are reviewed when a new spec version is
drafted or a stage is planned.

## Ideas

- **Fast-tier JS/TS linter (Biome or Oxlint):** If ESLint's fast-path performance misses its
  p95 < 2 s budget, consider adding Biome or Oxlint as a tier-F alternative that runs without
  type information. Per §12 D6, ESLint + typescript-eslint is the confirmed choice; this would
  be a supplementary fast pass, not a replacement.
