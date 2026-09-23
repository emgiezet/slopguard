# configs/baseline — example configurations

This directory contains one example configuration file for each linter and static-analysis
tool that Slop Guard can run. They are **examples**, not the plugin's operating defaults.

## What happens when your project ignores this directory

When your project has no configuration file for a given tool (for example, no `ruff.toml`,
no `.golangci.yml`), the dispatcher passes the baseline file to the tool but runs it as a
**security overlay**: only findings whose mapped category is `security`
(`rules/mapping/<tool>.yaml`) are forwarded to the agent. Style, maintainability, and
performance findings are silently dropped. A rule with no mapping entry is not treated as
security and is dropped too — defaulting unknown rules to security would reinstate exactly
the noise this removes.

The reason: a repository that never asked for our style rules should not receive them.
Security is what the guard is installed for.

## How to adopt a baseline config

```bash
slopguard adopt-config <tool>
```

This copies the file into your repository. From that point the dispatcher uses your copy and
reports everything the config finds — the security overlay no longer applies. The file is
treated like any other linter configuration: it travels with the repo and applies identically
in CI and on every developer's machine.

## Write protection after adoption

Once a baseline config is copied into your project, the `pre-write` hook treats it as a
protected file. The agent must ask for human approval before modifying it, so a later silent
relaxation (raising a threshold, disabling a rule category) requires a deliberate human
decision rather than a quiet edit.

If you want to return to security-only reporting for a tool, remove your copy of the config.
The dispatcher then falls back to the baseline as a security overlay again.

## Knob: `config_source`

Set `config_source` in the plugin options (or `.slopguard.json`) to change the fallback
behaviour for all tools at once:

| Value | Behaviour when no project config exists |
|---|---|
| `overlay` (default) | baseline runs as security overlay — only `security` findings |
| `full` | baseline runs and reports all findings |
| `project-only` | tool does not run at all |

Per-tool override is not supported; adopt the config to unlock all findings for a single tool.
