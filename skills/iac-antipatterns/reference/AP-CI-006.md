# AP-CI-006 — GitLab CI — images without digest, remote includes, or curl piped to shell

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
GitLab CI jobs that pull images without digest, include external YAML without an integrity hash, or execute downloaded scripts in `script:` blocks are vulnerable to supply-chain attacks. Pin images to digests, use `include: { integrity: }`, and verify downloaded scripts before running.

## Do Not Write
```yaml
image: ubuntu:latest
include:
  - remote: https://example.com/ci-template.yml
```

## Instead Write
```yaml
image: ubuntu:22.04@sha256:abc123def456...
# remote includes with integrity verification only
```

## Detection
- opengrep: `slopguard.gitlab.image-without-digest`
- opengrep: `slopguard.gitlab.include-remote`

