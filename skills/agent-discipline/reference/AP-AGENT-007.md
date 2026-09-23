# AP-AGENT-007 — Edits outside the targeted diff scope

**Category:** agent | **Severity:** warn

## Summary
Reformatting whole files, refactoring unrelated functions, or touching lines outside the failing hunks while fixing a specific issue creates noise in code review and may introduce regressions. Keep changes minimal and scoped to what the task requires.

## Do Not Write
# Reformatting an entire 500-line file while fixing a single bug
# Renaming variables throughout a file while adding a new feature

## Instead Write
# Change only the lines that directly address the requirement; leave surrounding code unchanged

