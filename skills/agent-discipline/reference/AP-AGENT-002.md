# AP-AGENT-002 — Lowering tool thresholds or growing lint baselines

**Category:** agent | **Severity:** error

## Summary
Reducing the PHPStan level, adding entries to a Psalm or ESLint baseline, or disabling linter rules to make the build green is treating the symptom, not the cause. Each such change must be explicitly approved by a human reviewer.

## Do Not Write
# Lowering phpstan level from 8 to 5 to suppress type errors
# Adding 20 new entries to phpstan-baseline.neon

## Instead Write
# Fix the actual code issue; if a suppression is needed, document why with a human reviewer

