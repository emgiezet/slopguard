# AP-AGENT-002 — Weakening a required test gate

**Category:** agent | **Severity:** error

## Summary
Dropping a coverage threshold, deleting a test or coverage step from CI, letting it fail open with continue-on-error, or turning slop-guard itself down removes the gate that proves the change works. Each needs a human decision. Loosening a linter or type-checker threshold is a different act — it is recorded in context, not gated, because a repository that ships daily changes those legitimately.

## Do Not Write
```
# fail_under = 90 → 60 in pyproject.toml to make the build green
# continue-on-error: true on the test job
```

## Instead Write
```
# Fix the code the gate rejects; move the threshold only as a reviewed decision
```

