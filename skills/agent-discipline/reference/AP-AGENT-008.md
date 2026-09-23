# AP-AGENT-008 — Using framework or library APIs without consulting current documentation

**Category:** agent | **Severity:** warn

## Summary
Framework APIs change between versions; using outdated method names or patterns from training data introduces bugs that are hard to diagnose. Before writing code against a framework, confirm the current API using Context7 documentation lookup.

## Do Not Write
# Writing Laravel 10 code in a project running Laravel 11 without checking migration guide

## Instead Write
# mcp__context7__resolve-library-id("laravel") → mcp__context7__get-library-docs(id, "routing")

