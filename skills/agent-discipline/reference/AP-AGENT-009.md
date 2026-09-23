# AP-AGENT-009 — New dependency pinned to @latest or a floating version range

**Category:** agent | **Severity:** error

## Summary
Specifying `@latest` or a loose range like `^1.0.0` means the installed version varies over time and across machines, breaking reproducibility and opening a window for supply-chain attacks when a new release is published. Pin every dependency to an explicit version in the lockfile.

## Do Not Write
npm install some-package@latest
go get github.com/example/lib@latest

## Instead Write
npm install some-package@3.2.1
go get github.com/example/lib@v3.2.1

