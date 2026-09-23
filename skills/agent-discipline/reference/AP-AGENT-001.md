# AP-AGENT-001 — Linter suppression comment without a reason

**Category:** agent | **Severity:** blocker

## Summary
Adding a suppression comment (nolint, noqa, @ts-ignore, phpstan-ignore, etc.) without a substantive reason hides a real finding without documenting why it is acceptable. Always include at least 10 characters of justification.

## Do Not Write
//nolint:gosec
# noqa

## Instead Write
//nolint:gosec // reason: value is a fixed compile-time constant, not user input
# noqa: S608 -- reason: raw SQL used only in internal migration script

