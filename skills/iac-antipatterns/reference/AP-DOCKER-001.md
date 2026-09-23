# AP-DOCKER-001 — Base image using :latest tag or no digest in production

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
The `latest` tag resolves to a different image over time, making builds non-deterministic and potentially pulling in breaking changes or supply-chain compromises. Pin the base image to a specific digest for production images.

## Do Not Write
```yaml
FROM node:latest
```

## Instead Write
```yaml
FROM node:20-alpine@sha256:abc123def456...
```

## Detection
- hadolint: `DL3007`
- hadolint: `DL3006`

