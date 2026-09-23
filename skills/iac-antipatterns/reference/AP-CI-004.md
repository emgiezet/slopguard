# AP-CI-004 — Missing or overly broad workflow permissions

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
Workflows without a `permissions:` block inherit the repository default, which often includes write access to the entire repository. Declare the minimum permissions each job needs at the job or workflow level.

## Do Not Write
```yaml
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    # no permissions block — inherits repository defaults
```

## Instead Write
```yaml
permissions:
  contents: read
jobs:
  build:
    permissions: { contents: read, packages: write }
```

## Detection
- zizmor: `excessive-permissions`

