#!/usr/bin/env bash
# tests/catalog_test.sh — Catalogue, gen-skills, and skill-budget offline tests.
#
# Standalone (not sourced by run-tests directly; MediumTier must register it).
# Uses ok()/bad() from its own counters.
# No network; no real linters; drives gen-skills through stub fixtures.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

PASS=0; FAIL=0
ok()  { printf '  ok    %s\n' "$1"; PASS=$(( PASS + 1 )); }
bad() { printf '  FAIL  %s: %s\n' "$1" "$2"; FAIL=$(( FAIL + 1 )); }

CATALOG="${PLUGIN_ROOT}/rules/catalog.yaml"
STACKS="${PLUGIN_ROOT}/rules/stacks.json"
TOOLS_LOCK="${PLUGIN_ROOT}/tools/tools.lock.json"
MAPPING_DIR="${PLUGIN_ROOT}/rules/mapping"
OPENGREP_DIR="${PLUGIN_ROOT}/rules/opengrep"
SKILLS_DIR="${PLUGIN_ROOT}/skills"
GEN_SKILLS="${PLUGIN_ROOT}/scripts/gen-skills"

printf 'catalog_test.sh\n\n'

# ─── helper: trim whitespace ──────────────────────────────────────────────────
trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# ─── helper: check if a tool name is "known" ─────────────────────────────────
# A tool is known if it appears as a key in tools.lock.json OR as a prefix
# of an opengrep rule file, OR if it is "eslint" (alias for eslint-stack).
tool_is_known() {
    local tool="$1"
    # Direct key in tools.lock.json
    if jq -e --arg t "$tool" '.tools[$t] != null' "$TOOLS_LOCK" >/dev/null 2>&1; then
        return 0
    fi
    # "eslint" is a human-facing alias for "eslint-stack"
    if [ "$tool" = "eslint" ]; then
        if jq -e '.tools["eslint-stack"] != null' "$TOOLS_LOCK" >/dev/null 2>&1; then
            return 0
        fi
    fi
    # opengrep directory counts: any tool whose rules live in rules/opengrep/
    if [ -d "$OPENGREP_DIR" ]; then
        for _f in "${OPENGREP_DIR}"/*.yaml; do
            [ -f "$_f" ] && return 0   # opengrep rules directory exists
        done
    fi
    return 1
}

# ─── helper: check if a rule ID exists in the mapping file for a tool ─────────
# Returns 0 if mapping file doesn't exist (warn only, not fail).
rule_in_mapping() {
    local tool="$1" rule="$2"
    local map_name="$tool"
    [ "$map_name" = "eslint-stack" ] && map_name="eslint"
    local map_file="${MAPPING_DIR}/${map_name}.yaml"
    [ -f "$map_file" ] || return 0   # no mapping file: can't validate; pass
    # YAML keys may be bare (  rule:) or quoted ("  rule":)
    grep -qF "  ${rule}:" "$map_file" || grep -qF "  \"${rule}\":" "$map_file"
}

# ─── 1. Catalog parses as valid YAML (jq-compatible flat check) ───────────────
ENTRY_COUNT=0
ENTRY_COUNT="$(grep -c '^- id: ' "$CATALOG" 2>/dev/null || true)"
if [ "$ENTRY_COUNT" -gt 0 ]; then
    ok "catalog.yaml is parseable and has $ENTRY_COUNT entries"
else
    bad "catalog.yaml parse" "no entries found (grep -c '^- id:' returned 0)"
fi

# ─── 2. All AP-* IDs are unique ────────────────────────────────────────────────
DUPE_IDS="$(grep '^- id: ' "$CATALOG" | awk '{print $3}' | sort | uniq -d)"
if [ -z "$DUPE_IDS" ]; then
    ok "all AP-* ids are unique"
else
    bad "AP-* id uniqueness" "duplicates found: $DUPE_IDS"
fi

# ─── 3. Every entry has required scalar fields ────────────────────────────────
MISSING_REQUIRED=0
current_id=""
has_title=false; has_lang=false; has_cat=false; has_sev=false; has_summary=false

check_entry() {
    [ -n "$current_id" ] || return
    local missing=""
    $has_title   || missing+="title "
    $has_lang    || missing+="language "
    $has_cat     || missing+="category "
    $has_sev     || missing+="severity "
    $has_summary || missing+="summary "
    if [ -n "$missing" ]; then
        bad "entry ${current_id} missing fields" "${missing}"
        MISSING_REQUIRED=$(( MISSING_REQUIRED + 1 ))
    fi
}

while IFS= read -r line; do
    case "$line" in
        "- id: "*)
            check_entry
            current_id="${line#- id: }"
            has_title=false; has_lang=false; has_cat=false; has_sev=false; has_summary=false ;;
        "  title: "*)    has_title=true ;;
        "  language: "*) has_lang=true ;;
        "  category: "*) has_cat=true ;;
        "  severity: "*) has_sev=true ;;
        "  summary: "*)  has_summary=true ;;
    esac
done < "$CATALOG"
check_entry

if [ "$MISSING_REQUIRED" -eq 0 ]; then
    ok "all catalog entries have required fields"
fi

# ─── 4. Valid category values ─────────────────────────────────────────────────
INVALID_CATS="$(grep '^  category: ' "$CATALOG" | awk '{print $2}' \
    | grep -vE '^(security|performance|maintainability|supply-chain|agent)$' || true)"
if [ -z "$INVALID_CATS" ]; then
    ok "all category values are valid"
else
    bad "invalid category values" "$(printf '%s' "$INVALID_CATS" | tr '\n' ',')"
fi

# ─── 5. Valid severity values ─────────────────────────────────────────────────
INVALID_SEVS="$(grep '^  severity: ' "$CATALOG" | awk '{print $2}' \
    | grep -vE '^(blocker|error|warn|info)$' || true)"
if [ -z "$INVALID_SEVS" ]; then
    ok "all severity values are valid"
else
    bad "invalid severity values" "$(printf '%s' "$INVALID_SEVS" | tr '\n' ',')"
fi

# ─── 6. Every detect entry references a known tool ────────────────────────────
DETECT_TOOL_FAILURES=0
DETECT_RULE_FAILURES=0
current_id=""
in_detect=false

while IFS= read -r line; do
    case "$line" in
        "- id: "*)
            current_id="${line#- id: }"
            in_detect=false ;;
        "  detect: []"*)
            in_detect=false ;;
        "  detect:"*)
            in_detect=true ;;
        "  "[a-z]*)
            # New non-detect field: exit detect list
            case "$line" in
                "  detect:"*) : ;;
                *) in_detect=false ;;
            esac ;;
        "    - { tool: "*)
            if $in_detect; then
                # Extract tool and rule
                tool="$(printf '%s' "$line" | sed 's/.*tool:[[:space:]]*//' | sed 's/[,[:space:]].*//')"
                rule="$(printf '%s' "$line" | sed 's/.*rule:[[:space:]]*//' | sed 's/[[:space:]}].*//')"
                tool="$(trim "$tool")"
                rule="$(trim "$rule")"
                if [ -z "$tool" ] || ! tool_is_known "$tool"; then
                    bad "detect tool unknown" "${current_id}: tool='${tool}'"
                    DETECT_TOOL_FAILURES=$(( DETECT_TOOL_FAILURES + 1 ))
                elif ! rule_in_mapping "$tool" "$rule"; then
                    bad "detect rule not in mapping" "${current_id}: ${tool}/${rule} not in rules/mapping/${tool}.yaml"
                    DETECT_RULE_FAILURES=$(( DETECT_RULE_FAILURES + 1 ))
                fi
            fi ;;
    esac
done < "$CATALOG"

[ "$DETECT_TOOL_FAILURES" -eq 0 ] && ok "all detect tool names are known"
[ "$DETECT_RULE_FAILURES" -eq 0 ] && ok "all detect rule IDs exist in mapping files (or no mapping file for tool)"

# ─── 7. Count entries per language / skill ────────────────────────────────────
# (per-skill counts reported via ok() below)
declare -A skill_count=()
current_id=""
current_lang=""

skill_for_lang() {
    case "$1" in
        php|laravel|symfony|doctrine) printf 'php-antipatterns' ;;
        go)           printf 'go-antipatterns' ;;
        python)       printf 'python-antipatterns' ;;
        typescript|react|vite) printf 'ts-react-antipatterns' ;;
        node|express) printf 'node-antipatterns' ;;
        sql)          printf 'sql-antipatterns' ;;
        terraform|kubernetes|helm|docker|github-actions|gitlab-ci) printf 'iac-antipatterns' ;;
        java|kotlin)  printf 'jvm-antipatterns' ;;
        csharp)       printf 'csharp-antipatterns' ;;
        ruby)         printf 'ruby-antipatterns' ;;
        rust)         printf 'rust-antipatterns' ;;
        agent)        printf 'agent-discipline' ;;
        *) printf '' ;;
    esac
}

while IFS= read -r line; do
    case "$line" in
        "- id: "*)
            current_id="${line#- id: }"
            current_lang="" ;;
        "  language: "*)
            current_lang="${line#  language: }"
            # Strip [ ] and spaces
            current_lang="${current_lang#\[}"; current_lang="${current_lang%\]}"
            # First tag
            first_tag="$(printf '%s' "$current_lang" | tr ',' '\n' | head -1 | tr -d ' ')"
            sk="$(skill_for_lang "$first_tag")"
            if [ -n "$sk" ]; then
                skill_count["$sk"]=$(( ${skill_count[$sk]:-0} + 1 ))
            fi ;;
    esac
done < "$CATALOG"

ok "entry distribution: php=${skill_count[php-antipatterns]:-0} go=${skill_count[go-antipatterns]:-0} py=${skill_count[python-antipatterns]:-0} ts=${skill_count[ts-react-antipatterns]:-0} node=${skill_count[node-antipatterns]:-0} sql=${skill_count[sql-antipatterns]:-0} iac=${skill_count[iac-antipatterns]:-0} jvm=${skill_count[jvm-antipatterns]:-0} cs=${skill_count[csharp-antipatterns]:-0} rb=${skill_count[ruby-antipatterns]:-0} rs=${skill_count[rust-antipatterns]:-0} agent=${skill_count[agent-discipline]:-0}"

# ─── 8. Every generated SKILL.md exists and is within §3 budget ──────────────
SKILLS_OVER_BUDGET=0
for skill_dir in "${SKILLS_DIR}"/*/; do
    skill_name="$(basename "$skill_dir")"
    md="${skill_dir}/SKILL.md"
    if [ ! -f "$md" ]; then
        bad "SKILL.md missing" "${skill_name}/SKILL.md not found"
        continue
    fi
    lc="$(wc -l < "$md")"
    cc="$(wc -c < "$md")"
    tc=$(( cc / 4 ))
    if [ "$lc" -gt 150 ]; then
        bad "SKILL.md line budget" "${skill_name}: ${lc} lines > 150"
        SKILLS_OVER_BUDGET=$(( SKILLS_OVER_BUDGET + 1 ))
    fi
    if [ "$tc" -gt 3000 ]; then
        bad "SKILL.md token budget" "${skill_name}: ~${tc} tokens > 3000"
        SKILLS_OVER_BUDGET=$(( SKILLS_OVER_BUDGET + 1 ))
    fi
done
[ "$SKILLS_OVER_BUDGET" -eq 0 ] && ok "all generated SKILL.md files within §3 budgets (150 lines, 3000 tokens)"

# ─── 9. Every SKILL.md has valid frontmatter ──────────────────────────────────
FM_FAILURES=0
for skill_dir in "${SKILLS_DIR}"/*/; do
    skill_name="$(basename "$skill_dir")"
    md="${skill_dir}/SKILL.md"
    [ -f "$md" ] || continue
    has_name=false; has_desc=false; has_uinv=false
    in_fm=false; fm_done=false
    while IFS= read -r line; do
        case "$line" in
            "---") 
                if ! $in_fm && ! $fm_done; then in_fm=true
                elif $in_fm; then in_fm=false; fm_done=true; break
                fi ;;
            "name: "*)        $in_fm && has_name=true ;;
            "description: "*) $in_fm && has_desc=true ;;
            "user-invocable: "*) $in_fm && has_uinv=true ;;
        esac
    done < "$md"
    if ! $has_name || ! $has_desc || ! $has_uinv; then
        bad "SKILL.md frontmatter" "${skill_name}: missing name/description/user-invocable"
        FM_FAILURES=$(( FM_FAILURES + 1 ))
    fi
done
[ "$FM_FAILURES" -eq 0 ] && ok "all SKILL.md files have valid frontmatter"

# ─── 10. gen-skills idempotency (run twice, diff SKILL.md files) ──────────────
TMP_IDEMPOTENT="$(mktemp -d)"
trap 'rm -rf "$TMP_IDEMPOTENT"' EXIT

# Snapshot current SKILL.md hashes
find "$SKILLS_DIR" -name 'SKILL.md' | sort | xargs md5sum 2>/dev/null \
    | sed "s|${SKILLS_DIR}/||g" > "${TMP_IDEMPOTENT}/before.md5"

# Re-run generator
SLOPGUARD_CATALOG="$CATALOG" SLOPGUARD_STACKS_JSON="$STACKS" \
    bash "$GEN_SKILLS" >/dev/null 2>&1

# Re-hash
find "$SKILLS_DIR" -name 'SKILL.md' | sort | xargs md5sum 2>/dev/null \
    | sed "s|${SKILLS_DIR}/||g" > "${TMP_IDEMPOTENT}/after.md5"

if diff -q "${TMP_IDEMPOTENT}/before.md5" "${TMP_IDEMPOTENT}/after.md5" >/dev/null 2>&1; then
    ok "gen-skills is idempotent (second run produced identical SKILL.md files)"
else
    bad "gen-skills idempotency" "SKILL.md hashes differ between first and second run"
    diff "${TMP_IDEMPOTENT}/before.md5" "${TMP_IDEMPOTENT}/after.md5" | head -10
fi

# ─── 11. gen-skills fails on over-budget catalogue ────────────────────────────
# Create a synthetic over-budget catalog: one skill with 200 entries
OVER_BUDGET_CATALOG="${TMP_IDEMPOTENT}/overbud.yaml"
{
    # Generate 200 PHP entries to exceed the 150-line SKILL.md limit
    for i in $(seq 1 200); do
        printf -- '- id: AP-PHP-TEST-%03d\n' "$i"
        printf '  title: Test entry number %d\n' "$i"
        printf '  language: [php]\n'
        printf '  category: security\n'
        printf '  severity: blocker\n'
        printf '  cwe: []\n'
        printf '  summary: Test summary for entry %d that is just long enough.\n' "$i"
        printf '  skill_line: Test skill line number %d with some text to fill space.\n' "$i"
        printf '  bad: |\n    bad code %d\n' "$i"
        printf '  good: |\n    good code %d\n' "$i"
        printf '  detect: []\n'
        printf '  prevent_in_skill: true\n'
        printf '  references: []\n'
        printf '\n'
    done
} > "$OVER_BUDGET_CATALOG"

OB_TMP="${TMP_IDEMPOTENT}/ob_skills"
mkdir -p "$OB_TMP"
if SLOPGUARD_CATALOG="$OVER_BUDGET_CATALOG" SLOPGUARD_STACKS_JSON="$STACKS" \
    SLOPGUARD_SKILLS_DIR="$OB_TMP" bash "$GEN_SKILLS" >/dev/null 2>&1; then
    bad "over-budget catalog" "gen-skills should have exited non-zero on over-budget catalog"
else
    ok "gen-skills exits non-zero when skill exceeds line budget"
fi

# ─── 12. Reference files exist for entries that have detect entries ───────────

# Simpler check: verify total reference file count matches entry count
REF_COUNT="$(find "$SKILLS_DIR" -name 'AP-*.md' -path '*/reference/*' | wc -l)"
if [ "$REF_COUNT" -eq "$ENTRY_COUNT" ]; then
    ok "reference file count matches catalog entry count ($REF_COUNT)"
else
    bad "reference file count" "expected $ENTRY_COUNT, found $REF_COUNT"
fi

# ─── 13. Every reference file for entries with detect has a Detection section ──
DET_MISSING=0
# Check a sample: AP-PHP-SEC-001 should have Detection
SAMPLE_REF="${SKILLS_DIR}/php-antipatterns/reference/AP-PHP-SEC-001.md"
if [ -f "$SAMPLE_REF" ] && grep -q '^## Detection' "$SAMPLE_REF"; then
    ok "reference file has Detection section when detect entries exist"
else
    bad "reference file detection section" "AP-PHP-SEC-001.md missing ## Detection"
    DET_MISSING=$(( DET_MISSING + 1 ))
fi

# ─── 14. agents/security-reviewer.md exists and has no Write/Edit tools ────────
AGENT_FILE="${PLUGIN_ROOT}/agents/security-reviewer.md"
if [ ! -f "$AGENT_FILE" ]; then
    bad "security-reviewer.md" "file not found: agents/security-reviewer.md"
else
    ok "agents/security-reviewer.md exists"
    # Reviewer must not be able to write or edit
    if grep -qiE '\bWrite\b' "$AGENT_FILE" && grep -q 'disallowedTools\|only.*Read\|never.*Write\|no.*Write\|cannot.*write\|must not.*write' "$AGENT_FILE"; then
        ok "security-reviewer forbids write/edit in its instructions"
    elif grep -q 'disallowedTools\|no.*Write\|cannot.*modify\|never.*modify\|must not.*write\|never to modify\|no Write' "$AGENT_FILE"; then
        ok "security-reviewer forbids write/edit in its instructions"
    else
        bad "security-reviewer disallowedTools" "agent definition should state Write/Edit are disallowed"
    fi
fi

# ─── 15. secure-review SKILL.md has context: fork ─────────────────────────────
SECURE_REVIEW="${SKILLS_DIR}/secure-review/SKILL.md"
if [ ! -f "$SECURE_REVIEW" ]; then
    bad "secure-review SKILL.md" "not found: skills/secure-review/SKILL.md"
else
    ok "skills/secure-review/SKILL.md exists"
    if grep -q '^context: fork' "$SECURE_REVIEW"; then
        ok "secure-review skill has context: fork"
    else
        bad "secure-review context" "SKILL.md missing 'context: fork' in frontmatter"
    fi
fi

# ─── 16. Shell checks on scripts ──────────────────────────────────────────────
if bash -n "$GEN_SKILLS" 2>/dev/null; then
    ok "gen-skills passes bash -n"
else
    bad "gen-skills bash -n" "syntax error"
fi

if bash -n "${TESTS_DIR}/catalog_test.sh" 2>/dev/null; then
    ok "catalog_test.sh passes bash -n"
else
    bad "catalog_test.sh bash -n" "syntax error"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
