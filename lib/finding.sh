#!/usr/bin/env bash
# lib/finding.sh — normalised finding record (§4.6) and atomic appender.
#
# Requires: lib/state.sh (state_dir, state_lock_acquire, state_lock_release).
#
# §4.6 finding fields (all required):
#   ap_id, tool, tool_rule, category, severity, cwe (JSON array),
#   file, line, end_line, message, fix, scope, fingerprint (computed).
#
# Fingerprint formula (spec §4.6 and brief):
#   sha256:$(printf '%s|%s|%s|%s' "$tool" "$tool_rule" "$file" "$snippet" | sha256sum)
#
# The snippet is used only for fingerprinting; it is not stored in the record.

# _finding_sha256_str <string>
# SHA-256 of a raw string (no trailing newline).  Tries sha256sum then shasum.
_finding_sha256_str() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    else
        printf 'slopguard: sha256sum or shasum is required\n' >&2
        return 1
    fi
}

# finding_add <session_id> <agent_id|--→ <ap_id> <tool> <tool_rule>
#             <category> <severity> <cwe_json_array>
#             <file> <line> <end_line>
#             <message> <fix> <scope>
#             <snippet>
#
# Appends one normalised finding to findings.json in the session directory.
# The append is atomic: mkdir lock → read → jq → mktemp → mv → release.
# Creates the directory and findings.json if absent.
# Pass '--' as agent_id to target the top-level session directory.
finding_add() {
    if [ "$#" -ne 15 ]; then
        printf 'slopguard: finding_add: expected 15 arguments, got %d\n' "$#" >&2
        return 1
    fi

    local session_id="$1"
    local agent_id="$2"
    local ap_id="$3"
    local tool="$4"
    local tool_rule="$5"
    local category="$6"
    local severity="$7"
    local cwe_json="$8"
    local file="$9"
    local line="${10}"
    local end_line="${11}"
    local message="${12}"
    local fix="${13}"
    local scope="${14}"
    local snippet="${15}"

    # Compute fingerprint per §4.6 and brief.
    local raw_fp fingerprint
    if ! raw_fp="$(_finding_sha256_str "${tool}|${tool_rule}|${file}|${snippet}")"; then
        printf 'slopguard: finding_add: SHA-256 failed\n' >&2
        return 1
    fi
    fingerprint="sha256:${raw_fp}"

    # Resolve and prepare the state directory.
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    mkdir -p "$dir"
    [ -f "${dir}/findings.json" ] || printf '[]\n' > "${dir}/findings.json"

    # Acquire the exclusive lock.
    if ! state_lock_acquire "$dir"; then
        printf 'slopguard: finding_add: lock timeout for %s\n' "$dir" >&2
        return 1
    fi

    # Append the finding atomically: jq into a temp file on the same filesystem,
    # then mv (atomic rename) over the live file.
    local tmp; tmp="$(mktemp "${dir}/.findings.XXXXXX")"
    local jq_ok=0
    jq \
        --arg     ap_id       "$ap_id"       \
        --arg     tool        "$tool"        \
        --arg     tool_rule   "$tool_rule"   \
        --arg     category    "$category"    \
        --arg     severity    "$severity"    \
        --argjson cwe         "$cwe_json"    \
        --arg     file        "$file"        \
        --argjson line        "$line"        \
        --argjson end_line    "$end_line"    \
        --arg     message     "$message"     \
        --arg     fix         "$fix"         \
        --arg     scope       "$scope"       \
        --arg     fingerprint "$fingerprint" \
        '. + [{
            ap_id:       $ap_id,
            tool:        $tool,
            tool_rule:   $tool_rule,
            category:    $category,
            severity:    $severity,
            cwe:         $cwe,
            file:        $file,
            line:        $line,
            end_line:    $end_line,
            message:     $message,
            fix:         $fix,
            scope:       $scope,
            fingerprint: $fingerprint
        }]' "${dir}/findings.json" > "$tmp" || jq_ok=$?

    if [ "$jq_ok" -ne 0 ]; then
        rm -f "$tmp"
        printf 'slopguard: finding_add: jq failed with %d\n' "$jq_ok" >&2
        state_lock_release "$dir"
        return 1
    fi

    mv "$tmp" "${dir}/findings.json"
    state_lock_release "$dir"
}
