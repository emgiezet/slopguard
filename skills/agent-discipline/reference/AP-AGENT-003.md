# AP-AGENT-003 — Disabling or deleting tests to make CI pass

**Category:** agent | **Severity:** error

## Summary
Skipping, marking as incomplete, or deleting test cases to clear a failing build hides real defects. Tests must be fixed by correcting the underlying code, not by removing the test.

## Do Not Write
it.skip('should validate token expiry')
@pytest.mark.skip(reason="flaky")

## Instead Write
# Fix the implementation so the test passes; remove the test only if the requirement changed

