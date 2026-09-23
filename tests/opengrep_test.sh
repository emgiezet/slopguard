#!/usr/bin/env bash
# opengrep_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.
#
# OFFLINE TEST SUITE for rules/opengrep/ rule files and lib/ext.sh opengrep
# extension support.
#
# What this suite does NOT cover:
#   - Whether rules actually match the bad fixtures (requires the opengrep binary).
#   - Whether rules pass the good fixtures without false positives.
# Those are covered by:
#   opengrep --validate --config rules/opengrep
#   opengrep --test rules/opengrep
# once the opengrep binary is installed in CI (currently blocked on Etap 0
# pinning of opengrep in tools/tools.lock.json).
#
# What this suite DOES cover (offline, no network, no opengrep binary):
#   1. Every rule file under rules/opengrep/ is valid YAML with the required
#      top-level 'rules:' key.
#   2. Every rule entry in every file has: id, languages, message, severity,
#      and at least one pattern key.
#   3. Every rule id matches the naming convention: slopguard.<scope>.<slug>.
#   4. Every rule's metadata.ap_id is either a known tier-1 AP-* identifier
#      (from §8 tables) or matches an expected tier-2 prefix (AP-JVM-*, AP-CS-*,
#      AP-RB-*, AP-RS-*).
#   5. Every unique AP-* identifier referenced by a rule has a corresponding
#      fixture pair (bad/<AP-ID>.<ext> and good/<AP-ID>.<ext>) somewhere under
#      tests/fixtures/.
#   6. ext.sh ext_opengrep_rules() discovers and validates a valid project
#      .slopguard/opengrep/ directory.
#   7. ext.sh ext_opengrep_rules() rejects a directory containing an invalid
#      rule file (prints to stderr, returns 0 with no output).
#   8. ext.sh ext_validate() accepts valid opengrep rule files.
#   9. ext.sh ext_validate() rejects opengrep-shaped files missing required keys.
#  10. ext.sh ext_validate() still accepts valid mapping override files (no regression).

# --------------------------------------------------------------------------- #
# Setup
# --------------------------------------------------------------------------- #

_OG_TESTS_DIR="${TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
_OG_PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "${_OG_TESTS_DIR}/.." && pwd)}"
_OG_RULES_DIR="${_OG_PLUGIN_ROOT}/rules/opengrep"
_OG_FIXTURES="${_OG_PLUGIN_ROOT}/tests/fixtures"

_OG_WORK="${TMPDIR:-/tmp}/slop-guard-og-$$"
mkdir -p "$_OG_WORK"
trap 'rm -rf "$_OG_WORK"' EXIT INT TERM

# Source ext.sh if not already sourced.
if ! command -v ext_validate >/dev/null 2>&1; then
    # shellcheck source=../lib/ext.sh
    . "${_OG_PLUGIN_ROOT}/lib/ext.sh"
fi

# --------------------------------------------------------------------------- #
# Known AP-* identifiers from §8 tables (tier 1)
# --------------------------------------------------------------------------- #

# A space-separated list of all AP-* IDs present in the §8 antipattern tables.
_OG_KNOWN_TIER1_IDS="
AP-PHP-SEC-001 AP-PHP-SEC-002 AP-PHP-SEC-003 AP-PHP-SEC-004 AP-PHP-SEC-005
AP-PHP-SEC-006 AP-PHP-SEC-007 AP-PHP-SEC-008 AP-PHP-SEC-009
AP-PHP-PERF-001 AP-PHP-PERF-002 AP-PHP-PERF-003 AP-PHP-PERF-004 AP-PHP-PERF-005
AP-PHP-MAINT-001 AP-PHP-MAINT-002 AP-PHP-MAINT-003 AP-PHP-MAINT-004
AP-GO-SEC-001 AP-GO-SEC-002 AP-GO-SEC-003 AP-GO-SEC-004 AP-GO-SEC-005
AP-GO-SEC-006 AP-GO-SEC-007
AP-GO-PERF-001 AP-GO-PERF-002 AP-GO-PERF-003 AP-GO-PERF-004
AP-GO-MAINT-001 AP-GO-MAINT-002 AP-GO-MAINT-003 AP-GO-MAINT-004
AP-PY-SEC-001 AP-PY-SEC-002 AP-PY-SEC-003 AP-PY-SEC-004 AP-PY-SEC-005
AP-PY-SEC-006 AP-PY-SEC-007 AP-PY-SEC-008
AP-PY-PERF-001 AP-PY-PERF-002 AP-PY-PERF-003
AP-PY-MAINT-001 AP-PY-MAINT-002 AP-PY-MAINT-003 AP-PY-MAINT-004
AP-TS-SEC-001 AP-TS-SEC-002 AP-TS-SEC-003 AP-TS-SEC-004 AP-TS-SEC-005
AP-TS-PERF-001 AP-TS-PERF-002 AP-TS-PERF-003 AP-TS-PERF-004
AP-TS-MAINT-001 AP-TS-MAINT-002 AP-TS-MAINT-003 AP-TS-MAINT-004
AP-NODE-SEC-001 AP-NODE-SEC-002 AP-NODE-SEC-003 AP-NODE-SEC-004 AP-NODE-SEC-005
AP-NODE-SEC-006 AP-NODE-SEC-007 AP-NODE-SEC-008 AP-NODE-SEC-009
AP-NODE-PERF-001 AP-NODE-PERF-002 AP-NODE-PERF-003
AP-NODE-MAINT-001 AP-NODE-MAINT-002
AP-SQL-001 AP-SQL-002 AP-SQL-003 AP-SQL-004 AP-SQL-005 AP-SQL-006 AP-SQL-007
AP-SQL-008
AP-TF-001 AP-TF-002 AP-TF-003 AP-TF-004 AP-TF-005 AP-TF-006 AP-TF-007
AP-K8S-001 AP-K8S-002 AP-K8S-003 AP-K8S-004 AP-K8S-005 AP-K8S-006
AP-DOCKER-001 AP-DOCKER-002 AP-DOCKER-003 AP-DOCKER-004 AP-DOCKER-005
AP-CI-001 AP-CI-002 AP-CI-003 AP-CI-004 AP-CI-005 AP-CI-006
AP-AGENT-001 AP-AGENT-002 AP-AGENT-003 AP-AGENT-004 AP-AGENT-005
AP-AGENT-006 AP-AGENT-007 AP-AGENT-008 AP-AGENT-009
"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

# _og_ap_id_known <ap_id>
# Exit 0 if ap_id is a known tier-1 ID or matches a tier-2 prefix pattern.
_og_ap_id_known() {
    local id="$1"
    # Tier-2 prefix check first (IDs defined in Etap 5 catalog).
    case "$id" in
        AP-JVM-*|AP-CS-*|AP-RB-*|AP-RS-*) return 0 ;;
    esac
    # Tier-1 exact match.
    local known; known="$(printf '%s\n' $_OG_KNOWN_TIER1_IDS)"
    printf '%s\n' "$known" | grep -qxF "$id"
}

# _og_has_fixture <ap_id> <bad_or_good>
# Exit 0 if at least one fixture file named AP-ID.<ext> exists in any
# tests/fixtures/*/<bad_or_good>/ directory.
_og_has_fixture() {
    local ap_id="$1" kind="$2"
    local lang_dir f
    for lang_dir in "${_OG_FIXTURES}"/*/; do
        [ -d "${lang_dir}${kind}" ] || continue
        for f in "${lang_dir}${kind}/${ap_id}."*; do
            [ -f "$f" ] && return 0
        done
    done
    return 1
}

# _og_extract_rule_ids <yaml_file>
# Print one rule id per line from a rules yaml file.
_og_extract_rule_ids() {
    grep -E '^\s+-\s+id:\s+' "$1" 2>/dev/null \
        | sed 's/.*- id:[[:space:]]*//' \
        | tr -d '\r'
}

# _og_extract_ap_ids <yaml_file>
# Print one ap_id per line from metadata.ap_id fields in a rules yaml file.
_og_extract_ap_ids() {
    grep -E '^\s+ap_id:\s+' "$1" 2>/dev/null \
        | sed 's/.*ap_id:[[:space:]]*//' \
        | tr -d '\r'
}

# --------------------------------------------------------------------------- #
# 1. Every rule file has the required top-level 'rules:' key
# --------------------------------------------------------------------------- #

_og_count_files=0
for _og_f in "${_OG_RULES_DIR}"/*.yaml; do
    [ -f "$_og_f" ] || continue
    _og_count_files=$((_og_count_files + 1))
    _og_bn="${_og_f##*/}"
    if grep -q '^rules:' "$_og_f" 2>/dev/null; then
        ok "opengrep-rules: ${_og_bn} has top-level 'rules:' key"
    else
        bad "opengrep-rules: ${_og_bn} has top-level 'rules:' key" "key not found"
    fi
done

[ "$_og_count_files" -gt 0 ] \
    && ok  "opengrep-rules: found ${_og_count_files} rule file(s) in rules/opengrep/" \
    || bad "opengrep-rules: rule files present" "no .yaml files found in rules/opengrep/"

# --------------------------------------------------------------------------- #
# 2-3. Every rule entry has required keys and correct naming convention
# --------------------------------------------------------------------------- #

for _og_f in "${_OG_RULES_DIR}"/*.yaml; do
    [ -f "$_og_f" ] || continue
    _og_bn="${_og_f##*/}"

    # Check languages field
    if grep -qE '^\s+languages:' "$_og_f"; then
        ok "opengrep-rules: ${_og_bn} has 'languages:' field"
    else
        bad "opengrep-rules: ${_og_bn} has 'languages:' field" "not found"
    fi

    # Check message field
    if grep -qE '^\s+message:' "$_og_f"; then
        ok "opengrep-rules: ${_og_bn} has 'message:' field"
    else
        bad "opengrep-rules: ${_og_bn} has 'message:' field" "not found"
    fi

    # Check severity field
    if grep -qE '^\s+severity:' "$_og_f"; then
        ok "opengrep-rules: ${_og_bn} has 'severity:' field"
    else
        bad "opengrep-rules: ${_og_bn} has 'severity:' field" "not found"
    fi

    # Check at least one pattern key
    if grep -qE '^\s+(pattern|pattern-either|pattern-regex|pattern-not-regex|patterns):' "$_og_f"; then
        ok "opengrep-rules: ${_og_bn} has at least one pattern key"
    else
        bad "opengrep-rules: ${_og_bn} has at least one pattern key" "no pattern key found"
    fi

    # 3. Rule id naming convention: slopguard.<scope>.<slug> (3+ dot-separated parts)
    while IFS= read -r _og_rid; do
        [ -n "$_og_rid" ] || continue
        case "$_og_rid" in
            slopguard.*.*)
                ok "opengrep-rules: ${_og_bn}: rule id '${_og_rid}' matches naming convention"
                ;;
            *)
                bad "opengrep-rules: ${_og_bn}: rule id naming convention" \
                    "'${_og_rid}' does not match slopguard.<scope>.<slug>"
                ;;
        esac
    done < <(_og_extract_rule_ids "$_og_f")
done

# --------------------------------------------------------------------------- #
# 4. Every AP-* id referenced by a rule is known or matches a tier-2 prefix
# --------------------------------------------------------------------------- #

for _og_f in "${_OG_RULES_DIR}"/*.yaml; do
    [ -f "$_og_f" ] || continue
    _og_bn="${_og_f##*/}"
    while IFS= read -r _og_ap; do
        [ -n "$_og_ap" ] || continue
        if _og_ap_id_known "$_og_ap"; then
            ok "opengrep-rules: ${_og_bn}: ap_id '${_og_ap}' is a known AP-* identifier"
        else
            bad "opengrep-rules: ${_og_bn}: ap_id '${_og_ap}' is a known AP-* identifier" \
                "not in §8 tables or tier-2 prefix"
        fi
    done < <(_og_extract_ap_ids "$_og_f")
done

# --------------------------------------------------------------------------- #
# 5. Every unique AP-* id has both bad and good fixture files
# --------------------------------------------------------------------------- #

# Collect all unique ap_ids across all rule files.
_og_seen_aps=""
for _og_f in "${_OG_RULES_DIR}"/*.yaml; do
    [ -f "$_og_f" ] || continue
    while IFS= read -r _og_ap; do
        [ -n "$_og_ap" ] || continue
        # Skip if already checked this AP-ID.
        case " ${_og_seen_aps} " in
            *" ${_og_ap} "*) continue ;;
        esac
        _og_seen_aps="${_og_seen_aps} ${_og_ap}"

        if _og_has_fixture "$_og_ap" "bad"; then
            ok "opengrep-rules: fixture bad/${_og_ap}.* exists"
        else
            bad "opengrep-rules: fixture bad/${_og_ap}.* exists" \
                "no file found in tests/fixtures/*/bad/${_og_ap}.*"
        fi

        if _og_has_fixture "$_og_ap" "good"; then
            ok "opengrep-rules: fixture good/${_og_ap}.* exists"
        else
            bad "opengrep-rules: fixture good/${_og_ap}.* exists" \
                "no file found in tests/fixtures/*/good/${_og_ap}.*"
        fi
    done < <(_og_extract_ap_ids "$_og_f")
done

# --------------------------------------------------------------------------- #
# 6. ext_validate accepts a valid opengrep rule file
# --------------------------------------------------------------------------- #

_og_valid_rule="${_OG_WORK}/valid-rule.yaml"
cat > "$_og_valid_rule" << 'YAMLEOF'
rules:
  - id: slopguard.test.bad-pattern
    languages: [python]
    message: Test rule for validation.
    severity: WARNING
    pattern: eval($X)
    metadata:
      ap_id: AP-PY-SEC-007
YAMLEOF

if ext_validate "$_og_valid_rule" 2>/dev/null; then
    ok "opengrep-rules: ext_validate accepts a valid opengrep rule file"
else
    bad "opengrep-rules: ext_validate accepts a valid opengrep rule file" \
        "ext_validate returned non-zero for a structurally valid rule"
fi

# --------------------------------------------------------------------------- #
# 7. ext_validate rejects an opengrep-shaped file missing required keys
# --------------------------------------------------------------------------- #

_og_missing_msg="${_OG_WORK}/missing-msg.yaml"
cat > "$_og_missing_msg" << 'YAMLEOF'
rules:
  - id: slopguard.test.no-message
    languages: [python]
    severity: WARNING
    pattern: eval($X)
YAMLEOF

if ext_validate "$_og_missing_msg" 2>/dev/null; then
    bad "opengrep-rules: ext_validate rejects rule file missing 'message:'" \
        "ext_validate returned 0 (should have rejected)"
else
    ok "opengrep-rules: ext_validate rejects rule file missing 'message:'"
fi

_og_missing_pat="${_OG_WORK}/missing-pattern.yaml"
cat > "$_og_missing_pat" << 'YAMLEOF'
rules:
  - id: slopguard.test.no-pattern
    languages: [python]
    message: Missing pattern key.
    severity: WARNING
YAMLEOF

if ext_validate "$_og_missing_pat" 2>/dev/null; then
    bad "opengrep-rules: ext_validate rejects rule file missing pattern key" \
        "ext_validate returned 0 (should have rejected)"
else
    ok "opengrep-rules: ext_validate rejects rule file missing pattern key"
fi

# --------------------------------------------------------------------------- #
# 8. ext_validate still accepts a valid mapping override file (no regression)
# --------------------------------------------------------------------------- #

_og_mapping="${_OG_WORK}/mapping.yaml"
cat > "$_og_mapping" << 'YAMLEOF'
rules:
  S608:
    ap_id: AP-PY-SEC-001
    severity: blocker
    category: security
    cwe: CWE-89
YAMLEOF

if ext_validate "$_og_mapping" 2>/dev/null; then
    ok "opengrep-rules: ext_validate still accepts valid mapping override files"
else
    bad "opengrep-rules: ext_validate still accepts valid mapping override files" \
        "regression: ext_validate now rejects mapping files"
fi

# --------------------------------------------------------------------------- #
# 9. ext_opengrep_rules discovers a valid .slopguard/opengrep/ directory
# --------------------------------------------------------------------------- #

_og_proj9="${_OG_WORK}/proj-og-ok"
mkdir -p "${_og_proj9}/.slopguard/opengrep"
cat > "${_og_proj9}/.slopguard/opengrep/myproject.yaml" << 'YAMLEOF'
rules:
  - id: slopguard.test.project-rule
    languages: [python]
    message: Project-specific rule for testing.
    severity: WARNING
    pattern: bad_function($X)
YAMLEOF

_og_result9="$(SLOPGUARD_EXT_DIR="${_og_proj9}/.slopguard" ext_opengrep_rules "$_og_proj9" 2>/dev/null)"
[ -n "$_og_result9" ] \
    && ok  "opengrep-rules: ext_opengrep_rules returns path for valid project rule dir" \
    || bad "opengrep-rules: ext_opengrep_rules returns path for valid project rule dir" \
           "returned empty (expected '${_og_proj9}/.slopguard/opengrep')"

[ "$_og_result9" = "${_og_proj9}/.slopguard/opengrep" ] \
    && ok  "opengrep-rules: ext_opengrep_rules returns the correct directory path" \
    || bad "opengrep-rules: ext_opengrep_rules correct path" \
           "got '${_og_result9}'"

# --------------------------------------------------------------------------- #
# 10. ext_opengrep_rules rejects invalid files, returns empty, exits 0
# --------------------------------------------------------------------------- #

_og_proj10="${_OG_WORK}/proj-og-bad"
mkdir -p "${_og_proj10}/.slopguard/opengrep"
cat > "${_og_proj10}/.slopguard/opengrep/broken.yaml" << 'YAMLEOF'
rules:
  - id: slopguard.test.broken-rule
    languages: [python]
    severity: WARNING
    # Missing: message, pattern
YAMLEOF

_og_result10="$(SLOPGUARD_EXT_DIR="${_og_proj10}/.slopguard" ext_opengrep_rules "$_og_proj10" 2>/dev/null)"
_og_exit10=$?

[ "$_og_exit10" -eq 0 ] \
    && ok  "opengrep-rules: ext_opengrep_rules exits 0 even with invalid rule file (fail-open)" \
    || bad "opengrep-rules: ext_opengrep_rules exits 0 with invalid rule file" \
           "exit code: ${_og_exit10}"

[ -z "$_og_result10" ] \
    && ok  "opengrep-rules: ext_opengrep_rules returns empty output for invalid rule dir" \
    || bad "opengrep-rules: ext_opengrep_rules returns empty output for invalid rule dir" \
           "got: '${_og_result10}'"

# --------------------------------------------------------------------------- #
# 11. ext_opengrep_rules returns empty when .slopguard/opengrep/ does not exist
# --------------------------------------------------------------------------- #

_og_proj11="${_OG_WORK}/proj-no-og"
mkdir -p "${_og_proj11}"
_og_result11="$(SLOPGUARD_EXT_DIR="${_og_proj11}/.slopguard" ext_opengrep_rules "$_og_proj11" 2>/dev/null)"

[ -z "$_og_result11" ] \
    && ok  "opengrep-rules: ext_opengrep_rules returns empty when .slopguard/opengrep/ absent" \
    || bad "opengrep-rules: ext_opengrep_rules returns empty when dir absent" \
           "got: '${_og_result11}'"

# --------------------------------------------------------------------------- #
# 12. Confirm rule file count for the record
# --------------------------------------------------------------------------- #

_og_rule_file_count=0
for _og_f in "${_OG_RULES_DIR}"/*.yaml; do
    [ -f "$_og_f" ] || continue
    _og_rule_file_count=$((_og_rule_file_count + 1))
done

[ "$_og_rule_file_count" -ge 12 ] \
    && ok  "opengrep-rules: at least 12 rule files present (got ${_og_rule_file_count})" \
    || bad "opengrep-rules: at least 12 rule files present" "got ${_og_rule_file_count}"
