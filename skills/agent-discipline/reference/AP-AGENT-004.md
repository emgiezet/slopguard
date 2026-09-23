# AP-AGENT-004 — Installing new dependencies without verification; curl piped to shell

**Category:** agent | **Severity:** blocker

## Summary
Adding a new package without verifying the maintainer, checking for typosquatting, and confirming the license introduces supply-chain risk. Piping a downloaded script directly to a shell executes unverified remote code. Both actions require explicit user confirmation.

## Do Not Write
npm install some-obscure-package@latest
curl https://install.example.com/setup.sh | bash

## Instead Write
# Ask the user; verify package name, maintainer, license, and age before installing

