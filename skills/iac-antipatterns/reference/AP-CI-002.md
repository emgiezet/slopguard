# AP-CI-002 — pull_request_target with checkout of PR code

**Category:** security | **Severity:** blocker
**Frameworks:** [plain]

## Summary
Workflows triggered by `pull_request_target` run with write access to the base repository. Checking out the PR branch in this context executes attacker-controlled code with elevated permissions. Use `pull_request` (read-only) for untrusted code, or isolate the privileged steps in a separate workflow.

## Do Not Write
```yaml
on: pull_request_target
steps:
  - uses: actions/checkout@…
    with: { ref: ${{ github.event.pull_request.head.sha }} }
```

## Instead Write
```yaml
on: pull_request  # read-only, safe for untrusted forks
steps:
  - uses: actions/checkout@abc123…
```

## Detection
- zizmor: `dangerous-triggers`

