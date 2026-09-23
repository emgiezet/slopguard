# AP-CI-003 — User-controlled data interpolated into run scripts

**Category:** security | **Severity:** blocker
**Frameworks:** [plain]

## Summary
Using `${{ github.event.* }}` directly inside a `run:` block allows an attacker to inject shell commands through a pull request title, issue comment, or branch name. Pass event data through an environment variable set in the `env:` block, which is not evaluated by the shell.

## Do Not Write
```yaml
run: echo "Branch ${{ github.head_ref }}"
```

## Instead Write
```yaml
env:
  BRANCH: ${{ github.head_ref }}
run: echo "Branch $BRANCH"
```

## Detection
- zizmor: `template-injection`

