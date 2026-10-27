# Playbook — adding a Slop Guard rule, catalogue entry or linter config

Task-scoped. Do not read sibling playbooks.
The full specification is `docs/slop-guard-spec.md`
(§4.9 catalogue schema, §6 mappings, §9.3 config validation, §10 content licensing).

## Sequence

1. **One id, one source.** Every `AP-*` id is born in `rules/catalog.yaml`.
   Required fields: `id`, `title`, `language`, `frameworks`, `category`,
   `severity`, `cwe`, `summary`, `skill_line`, `bad`, `good`, `detect`,
   `prevent_in_skill`, `references`.  Copy the nearest entry in the same
   section and keep ids sequential.  `detect: []` means prevention-only — say
   so; no pinned tool finds it.

2. **Write it from scratch.** Never paste rule text, examples or messages from
   Semgrep, SonarSource or OWASP.  CWE as `CWE-<n>` plus the `cwe.mitre.org`
   URL; OWASP as a link only.

3. **Detection wiring** (when `detect:` names a tool):
   - `rules/mapping/<tool>.yaml` maps its rule id to `ap_id`, `severity`,
     `category`, `cwe`.
   - An opengrep rule lives in `rules/opengrep/<lang>.yaml` with id
     `slopguard.<lang>[.<framework>].<slug>`.
   - A bad and a good sample in `tests/fixtures/<lang>/{bad,good}/` so the
     integration suite proves the tool fires on one and stays quiet on the
     other.

4. **New tool** — pin it in `tools/tools.lock.json` (`version`, `bin`,
   per-platform `url` + `sha256`), list it in the relevant stack's `tools`
   array in `rules/stacks.json` or in `SLOPGUARD_CORE_TOOLS`
   (`lib/detect.sh`).  `scripts/validate-configs` fails a pinned tool nothing
   reaches.

5. **Baseline config** goes in `configs/baseline/`; it is an example, not
   imposed.  Findings outside `category: security` are dropped by the security
   overlay unless the user adopts the config with `slopguard adopt-config`.

6. **Regenerate, never hand-edit**, the generated skills directories
   (`skills/*-antipatterns/`, `skills/agent-discipline/`).  Run
   `scripts/gen-skills`.  A new language tag that is a concern rather than a
   stack gets an explicit `skill_paths` case in `gen-skills`, not a fake entry
   in `rules/stacks.json`.

7. **Changelog.** One entry under `## Unreleased` in `CHANGELOG.md`: what
   changed, file by file, and a **Why** paragraph for any choice a reader
   would question.

## Test requirements

- `tests/catalog_test.sh` covers schema, known tools, mapping consistency,
  budgets and gen-skills idempotency — extend it only for a new invariant,
  not per entry.
- A detection change requires a fixture pair (step 3), proven by running
  `bash tests/tool-integration` after
  `bin/slopguard doctor --install --all` (CI treats skips as failures).
- A config change: `scripts/validate-configs` reports `PASS` for that tool,
  not `SKIP`.

## Verify

See `.claude/rules/catalog.md` for the full verification block.

## Done when

The entry exists once in `catalog.yaml`, its detection (if any) is mapped and
has a firing fixture, generated skills are regenerated and within the 150-line /
3000-token budget, the changelog says why, and `bash tests/catalog_test.sh` plus
`CI= bash tests/run-tests` are green.
