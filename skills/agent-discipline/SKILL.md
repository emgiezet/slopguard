---
name: agent-discipline
description: Always-on agent behavior rules: linter suppression policy, baseline changes, test deletion, dependency installs, credential handling, scope discipline.
user-invocable: false
---

# Agent discipline — always-on rules — do not write these

Enforced by pre-write and pre-bash policies. Full text on invocation.

## Blockers
- AP-AGENT-001 — Suppression comments require ≥10-char justification; bare suppressions are blocked pre-write.
- AP-AGENT-004 — All new dependency installs require confirmation; `curl | sh` is always blocked.
- AP-AGENT-005 — Reading `.env*`, private keys, and credential files is denied; find values via safe alternatives.
- AP-AGENT-006 — Use placeholder values in code examples; real credentials must never appear in written files.

## Errors
- AP-AGENT-002 — Tool threshold reductions and baseline additions require human review; do not change them to clear findings.
- AP-AGENT-003 — Fix failing tests by correcting the code; never skip, mark incomplete, or delete tests to clear CI.
- AP-AGENT-009 — Pin new dependencies to an explicit stable version; never use `@latest` or loose ranges.

## Warnings
- AP-AGENT-007 — Restrict edits to the lines required by the task; do not reformat or refactor out of scope.
- AP-AGENT-008 — Before calling any framework API, verify the version-specific docs via Context7.

Details for any ID: `reference/<ID>.md`
