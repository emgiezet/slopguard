# AP-CI-005 — persist-credentials on checkout in artifact-publishing jobs

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
When `persist-credentials` is left at its default (`true`), the Git token is available to subsequent steps. In jobs that build and publish artefacts, this token can be exfiltrated through the artefact contents. Set `persist-credentials: false` unless the job explicitly needs to push with the token.

## Do Not Write
```yaml
- uses: actions/checkout@abc123…
# persist-credentials defaults to true
```

## Instead Write
```yaml
- uses: actions/checkout@abc123…
  with: { persist-credentials: 'false' }
```

## Detection
- zizmor: `artipacked`

