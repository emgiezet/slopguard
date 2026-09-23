# AP-CI-001 — GitHub Actions steps pinned to a tag instead of a full SHA

**Category:** security | **Severity:** blocker
**Frameworks:** [plain]

## Summary
Pinning to a version tag like `actions/checkout@v4` is mutable — the tag can be moved to point at a different commit, as happened in the 2026 Trivy supply-chain incident. Pin every `uses:` to the full commit SHA to guarantee immutability.

## Do Not Write
```yaml
- uses: actions/checkout@v4
```

## Instead Write
```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

## Detection
- zizmor: `unpinned-uses`

