---
paths:
  - "rules/**"
  - "configs/**"
  - "skills/**"
  - "tools/**"
---

# Slop Guard — catalogue, mappings, configs and generated skills

## Conventions

- `rules/catalog.yaml` is the **only** source of `AP-*` ids.  Ids follow the
  pattern `AP-<LANG>-<AREA>-<NNN>` or `AP-<AREA>-<NNN>` (e.g. `AP-AGENT-002`,
  `AP-AUTH-007`, `AP-CI-001`).  Ids are never renumbered, never reused.
- Severity scale: `blocker | error | warn | info`.
  Categories: `security | performance | maintainability | supply-chain`.
  Security + CWE Top 25 → `blocker`.
- Rule text is **original**.  CWE by number with `cwe.mitre.org` URL; OWASP
  and vendor docs as links only.  Never paste text from Semgrep, SonarSource
  or OWASP.
- `skills/*-antipatterns/**` and `skills/agent-discipline/**` (`SKILL.md` and
  `reference/<ID>.md`) are **generated** by `scripts/gen-skills` — edit the
  catalogue and regenerate.  Hand-written skills: `deslop`, `secure-review`.
- Generated `SKILL.md` budget: ≤ 150 lines, ≤ 3000 tokens (≈ 4 chars/token);
  `gen-skills` fails over it.
- `rules/mapping/<tool>.yaml` maps the tool's rule id → `ap_id`, `severity`,
  `category`, `cwe`.  A tool-wide catch-all uses a bucket id ending `-000`
  with no catalogue page.
- `tools/tools.lock.json`: per tool a `version`, `bin` and `assets` keyed by
  platform (`linux/darwin × amd64/arm64`), each with a release `url` and
  `sha256`.  Every pinned tool is reachable from a stack in
  `rules/stacks.json` or from `SLOPGUARD_CORE_TOOLS` in `lib/detect.sh`.
- `configs/baseline/` are **examples**, not defaults imposed on a project.
  Without adoption, only `category: security` findings survive the overlay.

## Verification

```bash
scripts/gen-skills
scripts/gen-skills --check          # must be idempotent
git status --short skills           # every generated change must be intended
bash tests/catalog_test.sh
scripts/validate-configs            # PASS (not SKIP) for the tool you changed
CI= bash tests/run-tests
bash tests/tool-integration         # after: bin/slopguard doctor --install --all
```
