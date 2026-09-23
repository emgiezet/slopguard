#!/usr/bin/env bash
# lib/dispatch.sh — fast-tier tool dispatch (Etap 2, §11.3).
#
# Requires: lib/state.sh, lib/finding.sh, lib/diff.sh, lib/tools.sh.
# Invoked from hooks/post-write via bin/slopguard post-write --tier=fast.
#
# Tool resolution order (§9.1): project binary → plugin binary → PATH binary
# (only when version matches lockfile).  Each tool runs under a per-tool
# timeout (SLOPGUARD_FAST_TOOL_TIMEOUT, default 8 s) so one slow linter
# cannot exhaust the 20 s hook budget.
#
# §2 Z2 diff filter:
#   - maintainability / performance findings: only changed lines (git diff -U0).
#   - security findings outside changed lines: emitted once per session as
#     pre-existing scope with severity info.
#   - Untracked files: judged whole (no line filter).
#
# §4.7 output: the caller (hooks/post-write) formats findings into one line
# per finding.  dispatch_fast writes new findings (NDJSON, one JSON per line)
# to the file path passed as $5, and also persists them via finding_add.

# --------------------------------------------------------------------------- #
# Internal helpers
# --------------------------------------------------------------------------- #

# _dispatch_timeout
# Honour SLOPGUARD_FAST_TOOL_TIMEOUT (default 8 s).
_dispatch_timeout() { printf '%s' "${SLOPGUARD_FAST_TOOL_TIMEOUT:-8}"; }

# _dispatch_sha256 <string>
# SHA-256 of a raw string (no trailing newline).
_dispatch_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    else
        printf 'dispatch: sha256 unavailable\n' >&2
        return 1
    fi
}

# _dispatch_cwe_json <cwe_string>
# Convert a space-separated CWE list like "CWE-89 CWE-94" to a JSON array.
_dispatch_cwe_json() {
    local cwe="${1:-}"
    [ -z "$cwe" ] || [ "$cwe" = '""' ] || [ "$cwe" = "none" ] || [ "$cwe" = "-" ] && {
        printf '[]'; return
    }
    # Strip any surrounding quotes the YAML parser may have left.
    cwe="$(printf '%s' "$cwe" | tr -d '"'"'")"
    [ -z "$cwe" ] && { printf '[]'; return; }
    printf '[' 
    local first=1 tok
    for tok in $cwe; do
        [ "$first" -eq 1 ] || printf ','
        printf '"%s"' "$tok"
        first=0
    done
    printf ']'
}

# _dispatch_map_lookup <mapping_yaml> <rule_id>
# Look up a rule in the mapping YAML and print TAB-separated:
#   ap_id  severity  category  cwe
# Prints nothing and exits 1 if the rule is not mapped.
_dispatch_map_lookup() {
    local yaml="$1" target="$2"
    [ -f "$yaml" ] || return 1
    awk -v target="$target" '
        /^  [^ ]/ {
            # A 2-space-indented line is a rule key (4-space lines are fields).
            # Flush previous block if it matched.
            if (current == target && ap != "") {
                printf "%s\t%s\t%s\t%s\n", ap, sev, cat, cw
                exit
            }
            current = $1
            sub(/:$/, "", current)
            gsub(/^["'"'"']|["'"'"']$/, "", current)  # strip YAML quotes from key
            ap = ""; sev = ""; cat = ""; cw = ""
        }
        /^    ap_id:/    { ap  = $2 }
        /^    severity:/ { sev = $2 }
        /^    category:/ { cat = $2 }
        /^    cwe:/      {
            cw = $2
            gsub(/["'"'"']/, "", cw)   # strip YAML quotes from value
        }
        END {
            if (current == target && ap != "") {
                printf "%s\t%s\t%s\t%s\n", ap, sev, cat, cw
            }
        }
    ' "$yaml"
}

# _dispatch_default_severity <category>
# Apply §4.8 defaults when a rule is not in the mapping YAML.
_dispatch_default_severity() {
    local cat="${1:-security}"
    case "$cat" in
        security)      printf 'error' ;;
        performance)   printf 'warn' ;;
        maintainability) printf 'warn' ;;
        *)             printf 'warn' ;;
    esac
}

# _dispatch_fingerprint_seen <session_id> <agent_id> <fp_hex>
# Exit 0 if sha256:<fp_hex> already exists in findings.json.
_dispatch_fingerprint_seen() {
    local session_id="$1" agent_id="$2" fp="$3"
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    [ -f "${dir}/findings.json" ] || return 1
    jq -e --arg fp "sha256:${fp}" \
        'map(select(.fingerprint == $fp)) | length > 0' \
        "${dir}/findings.json" >/dev/null 2>&1
}

# _dispatch_preexisting_seen <session_id> <agent_id> <fp_hex>
# Exit 0 if the pre-existing marker file already exists (once-per-session gate).
_dispatch_preexisting_seen() {
    local session_id="$1" agent_id="$2" fp="$3"
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    [ -f "${dir}/.preexist-${fp}" ]
}

# _dispatch_preexisting_mark <session_id> <agent_id> <fp_hex>
_dispatch_preexisting_mark() {
    local session_id="$1" agent_id="$2" fp="$3"
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    mkdir -p "$dir"
    : > "${dir}/.preexist-${fp}"
}

# _dispatch_tool_unavail_seen <session_id> <agent_id> <tool>
_dispatch_tool_unavail_seen() {
    local session_id="$1" agent_id="$2" tool="$3"
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    [ -f "${dir}/.tool-unavail-${tool}" ]
}

# _dispatch_tool_unavail_mark <session_id> <agent_id> <tool>
_dispatch_tool_unavail_mark() {
    local session_id="$1" agent_id="$2" tool="$3"
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    mkdir -p "$dir"
    : > "${dir}/.tool-unavail-${tool}"
}

# _dispatch_emit  session_id agent_id ap_id tool tool_rule category severity
#                 cwe_json file line end_line message fix scope snippet
#                 findings_out
# Deduplicates by fingerprint; if new: calls finding_add + appends NDJSON.
_dispatch_emit() {
    local session_id="$1"  agent_id="$2"   ap_id="$3"     tool="$4"
    local tool_rule="$5"   category="$6"   severity="$7"  cwe_json="$8"
    local file="$9"        line="${10}"     end_line="${11}"
    local message="${12}"  fix="${13}"      scope="${14}"   snippet="${15}"
    local findings_out="${16}"

    # Fingerprint: sha256(tool|rule|file|snippet)
    local raw_fp
    raw_fp="$(_dispatch_sha256 "${tool}|${tool_rule}|${file}|${snippet}")" || return 0

    # Dedup: skip if fingerprint already in findings.json.
    if _dispatch_fingerprint_seen "$session_id" "$agent_id" "$raw_fp"; then
        return 0
    fi

    # Persist via finding_add.
    finding_add "$session_id" "$agent_id" \
        "$ap_id" "$tool" "$tool_rule" \
        "$category" "$severity" "$cwe_json" \
        "$file" "$line" "$end_line" \
        "$message" "$fix" "$scope" \
        "$snippet" || return 0

    # Append NDJSON line to findings_out (compact: one JSON object per line).
    jq -n -c \
        --arg     ap_id     "$ap_id"     \
        --arg     tool      "$tool"      \
        --arg     tool_rule "$tool_rule" \
        --arg     category  "$category"  \
        --arg     severity  "$severity"  \
        --argjson cwe       "$cwe_json"  \
        --arg     file      "$file"      \
        --argjson line      "$line"      \
        --argjson end_line  "$end_line"  \
        --arg     message   "$message"   \
        --arg     fix       "$fix"       \
        --arg     scope     "$scope"     \
        '{ap_id:$ap_id,tool:$tool,tool_rule:$tool_rule,category:$category,
          severity:$severity,cwe:$cwe,file:$file,line:$line,end_line:$end_line,
          message:$message,fix:$fix,scope:$scope}' >> "$findings_out" 2>/dev/null
}

# _dispatch_filter_emit  session_id agent_id ap_id tool tool_rule category severity
#                        cwe_json file line end_line message fix snippet
#                        is_untracked changed_ranges findings_out
# Apply Z2 line filter before emitting.
# shellcheck disable=SC2086  # (ranges expansion is intentional)
_dispatch_filter_emit() {
    local session_id="$1"  agent_id="$2"   ap_id="$3"     tool="$4"
    local tool_rule="$5"   category="$6"   severity="$7"  cwe_json="$8"
    local file="$9"        line="${10}"     end_line="${11}"
    local message="${12}"  fix="${13}"      snippet="${14}"
    local is_untracked="${15}"  changed_ranges="${16}"  findings_out="${17}"

    if [ "$is_untracked" -eq 1 ]; then
        # Untracked files: judge whole file.
        _dispatch_emit "$session_id" "$agent_id" \
            "$ap_id" "$tool" "$tool_rule" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$end_line" \
            "$message" "$fix" "changed-lines" "$snippet" \
            "$findings_out"
        return
    fi

    # Tracked file with diff filter.
    local in_range=0
    [ -z "$changed_ranges" ] || diff_line_in_ranges "$line" "$changed_ranges" && in_range=1

    if [ "$in_range" -eq 1 ]; then
        _dispatch_emit "$session_id" "$agent_id" \
            "$ap_id" "$tool" "$tool_rule" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$end_line" \
            "$message" "$fix" "changed-lines" "$snippet" \
            "$findings_out"
    elif [ "$category" = "security" ]; then
        # Security outside changed lines: emit once per session as pre-existing info.
        local snippet_trunc="${snippet:0:120}"
        local pre_fp
        pre_fp="$(_dispatch_sha256 "${tool}|${tool_rule}|${file}|${snippet_trunc}")" || return 0
        if ! _dispatch_preexisting_seen "$session_id" "$agent_id" "$pre_fp"; then
            _dispatch_preexisting_mark "$session_id" "$agent_id" "$pre_fp"
            _dispatch_emit "$session_id" "$agent_id" \
                "$ap_id" "$tool" "$tool_rule" \
                "security" "info" "$cwe_json" \
                "$file" "$line" "$end_line" \
                "$message" "$fix" "pre-existing" "${snippet_trunc}" \
                "$findings_out"
        fi
    fi
    # Performance/maintainability outside changed lines: silently filtered (Z2).
}

# _dispatch_config_filter_emit  config_mode  [all _dispatch_filter_emit args]
# Applies the security overlay before calling _dispatch_filter_emit.
#
# In overlay mode a finding is emitted only when its mapped category is "security".
# A rule with no mapping entry defaults to maintainability and is therefore dropped
# in overlay mode — defaulting unknowns to security would reinstate exactly the
# noise this feature removes.
# In "project" or "full" mode every finding passes through unchanged.
# "skip" is handled by each runner before calling this function and never reaches here.
# shellcheck disable=SC2086  # intentional positional expansion via "$@"
_dispatch_config_filter_emit() {
    local _dcfe_mode="$1"; shift
    # After shift: $1=session_id $2=agent_id $3=ap_id $4=tool $5=tool_rule
    #              $6=category $7=severity $8=cwe_json …
    if [ "$_dcfe_mode" = "overlay" ] && [ "${6}" != "security" ]; then
        return 0
    fi
    _dispatch_filter_emit "$@"
}

# --------------------------------------------------------------------------- #
# Tool-specific runners
# --------------------------------------------------------------------------- #

# _dispatch_run_ruff  file session_id agent_id project_dir
#                     is_untracked changed_ranges findings_out
_dispatch_run_ruff() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool ruff 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" ruff; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" ruff
            printf 'slopguard: ruff unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path ruff "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode ruff "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local raw exit_code=0
    raw="$(timeout "$(_dispatch_timeout)" \
        "$tool_bin" check --config "$config" --output-format=json --no-fix --exit-zero \
        "$file" 2>/dev/null)" || exit_code=$?
    # exit_code 124 = timeout (fail-open), others = tool error (fail-open).
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/ruff.yaml"

    local code msg row end_row snippet ap_id severity category cwe_json fix
    # Parse the JSON array using jq, emit one TSV line per finding.
    while IFS=$'\t' read -r code msg row end_row; do
        [ -n "$code" ] || continue

        snippet="$(printf '%s' "$msg" | head -c 120)"
        local lookup; lookup="$(_dispatch_map_lookup "$mapping" "$code")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-PY-LINT-000"
            category="maintainability"
            severity="$(_dispatch_default_severity "$category")"
            cwe_json='[]'
        fi
        fix=""

        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "ruff" "$code" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$row" "$end_row" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.[] | [.code, .message, (.location.row|tostring), (.end_location.row // .location.row|tostring)] | @tsv' 2>/dev/null || true)"
}

# _dispatch_run_eslint_stack  file session_id agent_id project_dir
#                             is_untracked changed_ranges findings_out
_dispatch_run_eslint_stack() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool eslint-stack 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" eslint-stack; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" eslint-stack
            printf 'slopguard: eslint-stack unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path eslint-stack "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode eslint-stack "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local raw exit_code=0
    raw="$(timeout "$(_dispatch_timeout)" \
        "$tool_bin" --config "$config" --format json --no-warn-ignored \
        "$file" 2>/dev/null)" || exit_code=$?
    # 0 = ok/warnings only, 1 = errors, 2 = fatal; 124 = timeout.
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/eslint.yaml"

    local rule_id msg line endline ap_id severity category cwe_json fix snippet
    while IFS=$'\t' read -r rule_id msg line endline; do
        [ -n "$rule_id" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        local lookup; lookup="$(_dispatch_map_lookup "$mapping" "$rule_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-TS-LINT-000"
            category="maintainability"
            severity="$(_dispatch_default_severity "$category")"
            cwe_json='[]'
        fi
        fix=""

        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "eslint" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "${endline:-$line}" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.[] | .messages[] | [.ruleId // "unknown", .message, (.line|tostring), ((.endLine // .line)|tostring)] | @tsv' 2>/dev/null || true)"
}

# _dispatch_run_hadolint  file session_id agent_id project_dir
#                         is_untracked changed_ranges findings_out
_dispatch_run_hadolint() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool hadolint 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" hadolint; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" hadolint
            printf 'slopguard: hadolint unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path hadolint "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode hadolint "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local raw exit_code=0
    raw="$(timeout "$(_dispatch_timeout)" \
        "$tool_bin" --config "$config" -f json "$file" 2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/hadolint.yaml"

    local code msg line ap_id severity category cwe_json fix snippet
    while IFS=$'\t' read -r code msg line; do
        [ -n "$code" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        local lookup; lookup="$(_dispatch_map_lookup "$mapping" "$code")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-DOCKER-LINT-000"
            category="maintainability"
            severity="warn"
            cwe_json='[]'
        fi
        fix=""

        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "hadolint" "$code" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$line" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.[] | [.code, .message, (.line|tostring)] | @tsv' 2>/dev/null || true)"
}

# _dispatch_run_kube_linter  file session_id agent_id project_dir
#                             is_untracked changed_ranges findings_out
_dispatch_run_kube_linter() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool kube-linter 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" kube-linter; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" kube-linter
            printf 'slopguard: kube-linter unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path kube-linter "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode kube-linter "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local raw exit_code=0
    raw="$(timeout "$(_dispatch_timeout)" \
        "$tool_bin" lint --config "$config" --format json "$file" 2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/kube-linter.yaml"

    local check msg ap_id severity category cwe_json fix snippet
    while IFS=$'\t' read -r check msg; do
        [ -n "$check" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        local lookup; lookup="$(_dispatch_map_lookup "$mapping" "$check")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-K8S-LINT-000"
            category="security"
            severity="warn"
            cwe_json='[]'
        fi
        fix=""

        # kube-linter has no line numbers in JSON output; use 0.
        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "kube-linter" "$check" \
            "$category" "$severity" "$cwe_json" \
            "$file" "0" "0" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.Reports[]? | [.Check, (.Diagnostic.Message // "")] | @tsv' 2>/dev/null || true)"
}

# _dispatch_run_zizmor  file session_id agent_id project_dir
#                        is_untracked changed_ranges findings_out
_dispatch_run_zizmor() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool zizmor 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" zizmor; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" zizmor
            printf 'slopguard: zizmor unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path zizmor "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode zizmor "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local raw exit_code=0
    raw="$(timeout "$(_dispatch_timeout)" \
        "$tool_bin" --config "$config" --format json --offline \
        "$file" 2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/zizmor.yaml"

    local rule_id msg line ap_id severity category cwe_json fix snippet
    while IFS=$'\t' read -r rule_id msg line; do
        [ -n "$rule_id" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        local lookup; lookup="$(_dispatch_map_lookup "$mapping" "$rule_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-CI-LINT-000"
            category="security"
            severity="error"
            cwe_json='[]'
        fi
        fix=""

        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "zizmor" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$line" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.diagnostics[]? |
            .ident as $id |
            .finding.message as $msg |
            ((.finding.locations[0].line_range.start.line // 0) | tostring) as $ln |
            [$id, $msg, $ln] | @tsv' 2>/dev/null || true)"
}

# --------------------------------------------------------------------------- #
# Extension descriptor runners (require ext.sh to be sourced)
# --------------------------------------------------------------------------- #

# _dispatch_run_one_ext_tool  desc_json file session_id agent_id project_dir
#                              is_untracked changed_ranges findings_out
# Run one validated project-descriptor tool and emit findings through the normal
# pipeline.  Always exits 0 (fail-open).
_dispatch_run_one_ext_tool() {
    local desc_json="$1" file="$2" session_id="$3" agent_id="$4"
    local project_dir="$5" is_untracked="$6" changed_ranges="$7" findings_out="$8"

    local name resolved timeout_val jq_expr
    name="$(printf '%s' "$desc_json"      | jq -r '.name'              2>/dev/null)"
    resolved="$(printf '%s' "$desc_json"  | jq -r '.resolved'          2>/dev/null)"
    timeout_val="$(printf '%s' "$desc_json" | jq -r '.run.timeout // 8' 2>/dev/null)"
    jq_expr="$(printf '%s' "$desc_json"   | jq -r '.parse.jq'          2>/dev/null)"

    if [ -z "$resolved" ] || [ ! -x "$resolved" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" "ext:${name}"; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" "ext:${name}"
            printf 'slopguard: ext tool %s: binary not found (skip)\n' "$name" >&2
        fi
        return 0
    fi

    # Build argv array from JSON, substituting {file} as one whole element.
    # No shell interpolation: each element is passed directly to exec.
    local args_json; args_json="$(printf '%s' "$desc_json" | jq -c '.run.args' 2>/dev/null)"
    local arg_count; arg_count="$(printf '%s' "$args_json" | jq 'length' 2>/dev/null || printf '0')"
    local cmd_args=() i arg
    for i in $(seq 0 $((arg_count - 1))); do
        arg="$(printf '%s' "$args_json" | jq -r --argjson idx "$i" '.[$idx]' 2>/dev/null)"
        if [ "$arg" = '{file}' ]; then
            cmd_args+=("$file")
        else
            cmd_args+=("$arg")
        fi
    done

    # Run under timeout (fail-open: treat non-0/1 exit as no output).
    local raw exit_code=0
    raw="$(timeout "$timeout_val" "$resolved" "${cmd_args[@]}" 2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    # Apply descriptor's jq expression to produce finding objects.
    local parsed_nd
    parsed_nd="$(printf '%s' "$raw" | jq -c "${jq_expr}" 2>/dev/null || true)"
    [ -n "$parsed_nd" ] || return 0

    # Load merged mapping for this tool (once per ext tool run).
    local mapping_nd; mapping_nd="$(ext_load_mapping "$project_dir" "$name")"

    # For each finding object extract rule, line, message.
    local findings_tsv
    findings_tsv="$(printf '%s' "$parsed_nd" \
        | jq -r '[.rule // "unknown", .message // "", ((.line // 0)|tostring)] | @tsv' \
        2>/dev/null || true)"

    local rule_id msg_txt line_no
    while IFS=$'\t' read -r rule_id msg_txt line_no; do
        [ -n "$rule_id" ] || continue

        # Look up rule in merged mapping.
        local ap_id severity category cwe_str cwe_json map_line
        map_line="$(printf '%s' "$mapping_nd" \
            | jq -r --arg r "$rule_id" \
                'select(.rule == $r) | [.ap_id, .severity, .category, .cwe] | @tsv' \
            2>/dev/null)"

        if [ -n "$map_line" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$map_line"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            # Neutral default: unmapped rule → warn maintainability, no ap_id.
            ap_id=""
            category="maintainability"
            severity="warn"
            cwe_json='[]'
        fi

        local snippet; snippet="$(printf '%s' "$msg_txt" | head -c 120)"

        _dispatch_filter_emit \
            "$session_id" "$agent_id" "$ap_id" "$name" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line_no" "$line_no" "$msg_txt" "" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$findings_tsv"
}

# _dispatch_run_ext_descriptors  file session_id agent_id project_dir
#                                 is_untracked changed_ranges findings_out
# Run all project descriptor tools whose globs match file and whose stacks
# (when specified) intersect SG_STACKS.  Always exits 0.
_dispatch_run_ext_descriptors() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local ext_d; ext_d="$(ext_dir "$project_dir")"
    [ -d "${ext_d}/tools" ] || return 0

    local tools_nd; tools_nd="$(ext_tools "$project_dir")"
    [ -n "$tools_nd" ] || return 0

    # Relative file path for glob matching.
    local file_rel="$file"
    [ "${file#${project_dir}/}" != "$file" ] && file_rel="${file#${project_dir}/}"

    local desc_line
    while IFS= read -r desc_line; do
        [ -n "$desc_line" ] || continue

        # Only run descriptors resolved as ok.
        local status; status="$(printf '%s' "$desc_line" | jq -r '.status' 2>/dev/null)"
        [ "$status" = "ok" ] || continue

        # Glob match: any pattern in match.globs must match.
        local matched=0 glob globs_out
        globs_out="$(printf '%s' "$desc_line" \
            | jq -r '.match.globs // [] | .[]' 2>/dev/null || true)"
        while IFS= read -r glob; do
            [ -n "$glob" ] || continue
            _ext_glob_match "$glob" "$file_rel" && { matched=1; break; }
        done <<< "$globs_out"
        [ "$matched" -eq 1 ] || continue

        # Stack intersection: only when descriptor specifies stacks AND SG_STACKS is set.
        local stacks_json; stacks_json="$(printf '%s' "$desc_line" \
            | jq -c '.match.stacks // []' 2>/dev/null)"
        if [ "$stacks_json" != '[]' ] && [ "$stacks_json" != 'null' ] \
            && [ -n "${SG_STACKS:-}" ]; then
            local stack_ok=0 dstack stacks_out
            stacks_out="$(printf '%s' "$stacks_json" | jq -r '.[]' 2>/dev/null || true)"
            while IFS= read -r dstack; do
                [ -n "$dstack" ] || continue
                case " ${SG_STACKS} " in *" ${dstack} "*) stack_ok=1; break ;; esac
            done <<< "$stacks_out"
            [ "$stack_ok" -eq 1 ] || continue
        fi

        _dispatch_run_one_ext_tool "$desc_line" "$file" \
            "$session_id" "$agent_id" "$project_dir" \
            "$is_untracked" "$changed_ranges" "$findings_out" || true
    done <<< "$tools_nd"
}


# --------------------------------------------------------------------------- #
# Tool selection
# --------------------------------------------------------------------------- #

# _dispatch_tools_for_file <file>
# Print a space-separated list of tool names applicable to this file.
# Routing is primarily by extension / filename pattern; stacks refine K8s vs CI.
_dispatch_tools_for_file() {
    local file="$1"
    local filename="${file##*/}"
    local ext="${filename##*.}"
    local tools=""

    # Python
    case "$ext" in
        py) tools="${tools} ruff" ;;
    esac

    # JavaScript / TypeScript
    case "$ext" in
        js|mjs|cjs|jsx|ts|mts|cts|tsx)
            tools="${tools} eslint-stack" ;;
    esac

    # Dockerfile (by name or extension)
    case "$filename" in
        Dockerfile|*.dockerfile|Dockerfile.*)
            tools="${tools} hadolint" ;;
    esac
    # Also catch paths like path/to/Dockerfile
    case "$file" in
        */Dockerfile|*/Dockerfile.*)
            case "$tools" in *hadolint*) ;; *) tools="${tools} hadolint" ;; esac ;;
    esac

    # YAML: GitHub Actions → zizmor, K8s manifests → kube-linter
    case "$ext" in
        yaml|yml)
            case "$file" in
                */.github/workflows/*.yml|*/.github/workflows/*.yaml|\
                .github/workflows/*.yml|.github/workflows/*.yaml)
                    tools="${tools} zizmor" ;;
                *)
                    # K8s manifests: detect by content.
                    if [ -f "$file" ] \
                        && grep -q 'apiVersion:' "$file" 2>/dev/null \
                        && grep -q 'kind:' "$file" 2>/dev/null; then
                        tools="${tools} kube-linter"
                    fi
                    ;;
            esac
            ;;
    esac

    printf '%s' "${tools# }"
}

# --------------------------------------------------------------------------- #
# Public entry point
# --------------------------------------------------------------------------- #

# dispatch_fast <file> <session_id> <agent_id> <project_dir> <findings_out>
#
# Runs all fast-tier tools applicable to <file>, applies the Z2 diff filter,
# deduplicates by fingerprint, persists new findings via finding_add, and
# writes new findings as NDJSON (one JSON object per line) to <findings_out>.
# Always exits 0 (fail-open, §2 Z6).
dispatch_fast() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="${4:-.}"
    local findings_out="$5"

    # Guard: file must exist and be readable.
    [ -f "$file" ] || return 0

    # Determine diff context.
    local is_untracked=0
    diff_is_untracked "$file" "$project_dir" 2>/dev/null && is_untracked=1

    local changed_ranges=""
    if [ "$is_untracked" -eq 0 ]; then
        changed_ranges="$(diff_changed_ranges "$file" "$project_dir" 2>/dev/null || true)"
    fi

    # Select and run pinned fast-tier tools for this file.
    local tools; tools="$(_dispatch_tools_for_file "$file")"
    local tool
    for tool in $tools; do
        local fn="_dispatch_run_${tool//-/_}"
        if command -v "$fn" >/dev/null 2>&1 || declare -f "$fn" >/dev/null 2>&1; then
            "$fn" "$file" "$session_id" "$agent_id" "$project_dir" \
                "$is_untracked" "$changed_ranges" "$findings_out" || true
        fi
    done

    # Run project-descriptor tools when ext.sh is sourced.
    if declare -f ext_tools >/dev/null 2>&1; then
        _dispatch_run_ext_descriptors \
            "$file" "$session_id" "$agent_id" "$project_dir" \
            "$is_untracked" "$changed_ranges" "$findings_out" || true
    fi

    return 0
}

# =========================================================================== #
# Medium-tier dispatcher (Etap 3, §11.3)
# =========================================================================== #

# --------------------------------------------------------------------------- #
# Medium-tier helpers
# --------------------------------------------------------------------------- #

# _dispatch_medium_timeout
# Per-tool timeout for medium-tier tools (default 45 s).
_dispatch_medium_timeout() { printf '%s' "${SLOPGUARD_MEDIUM_TOOL_TIMEOUT:-45}"; }

# _dispatch_medium_pending_key <session_id> <agent_id> <file>
# Print the path to the debounce token file for this file.
_dispatch_medium_pending_key() {
    local session_id="$1" agent_id="$2" file="$3"
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    local fhash; fhash="$(_dispatch_sha256 "$file" 2>/dev/null | head -c16 || printf 'nohash')"
    printf '%s/.medium-pending-%s' "$dir" "$fhash"
}

# --------------------------------------------------------------------------- #
# Medium-tier tool runners
# --------------------------------------------------------------------------- #

# _dispatch_run_phpstan  file session_id agent_id project_dir
#                        is_untracked changed_ranges findings_out
_dispatch_run_phpstan() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool phpstan 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" phpstan; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" phpstan
            printf 'slopguard: phpstan unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path phpstan "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode phpstan "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    # New/untracked files use --level=max per spec §6.1.
    local level_args=""
    [ "$is_untracked" -eq 1 ] && level_args="--level=max"

    local raw exit_code=0
    raw="$(timeout "$(_dispatch_medium_timeout)" \
        "$tool_bin" analyse --error-format=json --no-progress --memory-limit=1G \
        -c "$config" $level_args "$file" 2>/dev/null)" || exit_code=$?
    # 0 = no errors, 1 = errors found; others = tool crash/config error → fail-open.
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/phpstan.yaml"

    local rule_id msg line ap_id severity category cwe_str cwe_json fix snippet lookup
    while IFS=$'\t' read -r rule_id msg line; do
        [ -n "$rule_id" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        lookup="$(_dispatch_map_lookup "$mapping" "$rule_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-PHP-LINT-000"
            category="maintainability"
            severity="$(_dispatch_default_severity "$category")"
            cwe_json='[]'
        fi
        fix=""
        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "phpstan" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$line" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.files // {} | to_entries[] |
            .value.messages[] |
            [(.identifier // "phpstan-error"), .message, (.line|tostring)] | @tsv' \
        2>/dev/null || true)"
}

# _dispatch_run_golangci_lint  file session_id agent_id project_dir
#                               is_untracked changed_ranges findings_out
# Runs on the Go package containing file.  For tracked files uses
# --new-from-rev=HEAD (Z2 natively); for untracked runs without it.
_dispatch_run_golangci_lint() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool golangci-lint 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" golangci-lint; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" golangci-lint
            printf 'slopguard: golangci-lint unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path golangci-lint "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode golangci-lint "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0

    # Compute the Go package path relative to project_dir.
    local file_dir; file_dir="$(dirname "$file")"
    local pkg_arg="./..."
    local _suffix="${file_dir#${project_dir}}"
    case "$_suffix" in
        /*)
            # file_dir is under project_dir; strip leading slash.
            _suffix="${_suffix#/}"
            [ -n "$_suffix" ] && pkg_arg="./${_suffix}/..." || pkg_arg="./..."
            ;;
        *) pkg_arg="./..." ;;  # not under project_dir or same
    esac

    # --new-from-rev=HEAD implements Z2 natively for tracked files (spec §6.2).
    local rev_arg=""
    [ "$is_untracked" -eq 0 ] && rev_arg="--new-from-rev=HEAD"

    local raw exit_code=0
    raw="$(timeout "$(_dispatch_medium_timeout)" \
        "$tool_bin" run --config "$config" \
        --output.json.path=stdout --show-stats=false \
        $rev_arg "$pkg_arg" 2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/golangci-lint.yaml"

    # With --new-from-rev=HEAD the tool already applied Z2; pass empty ranges so
    # _dispatch_filter_emit treats every finding as in-range.
    local eff_untracked="$is_untracked"
    local eff_changed_ranges="$changed_ranges"
    [ "$is_untracked" -eq 0 ] && eff_changed_ranges=""

    local rule_id msg line fname ap_id severity category cwe_str cwe_json fix snippet lookup
    while IFS=$'\t' read -r rule_id msg line fname; do
        [ -n "$rule_id" ] || continue
        # Resolve finding file to absolute path.
        local finding_file
        case "$fname" in
            /*) finding_file="$fname" ;;
            *)  finding_file="${project_dir}/${fname}" ;;
        esac
        snippet="$(printf '%s' "$msg" | head -c 120)"
        lookup="$(_dispatch_map_lookup "$mapping" "$rule_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-GO-LINT-000"
            category="maintainability"
            severity="$(_dispatch_default_severity "$category")"
            cwe_json='[]'
        fi
        fix=""
        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "golangci-lint" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$finding_file" "$line" "$line" "$msg" "$fix" "$snippet" \
            "$eff_untracked" "$eff_changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.Issues[]? |
            (if .FromLinter == "gosec" then
                "gosec:" + (.Text |
                    [match("G[0-9]+")] |
                    if length > 0 then .[0].string else "" end)
             else .FromLinter
             end) as $rule_id |
            [$rule_id, .Text, (.Pos.Line|tostring), (.Pos.Filename // "")] | @tsv' \
        2>/dev/null || true)"
}

# _dispatch_run_eslint_typed  file session_id agent_id project_dir
#                              is_untracked changed_ranges findings_out
# Like eslint-stack but with SLOPGUARD_TYPED_LINT=1; uses eslint-typed.yaml
# first, falls back to eslint.yaml for common rules.
_dispatch_run_eslint_typed() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool eslint-stack 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" eslint-typed; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" eslint-typed
            printf 'slopguard: eslint (typed) unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path eslint-stack "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode eslint-stack "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local raw exit_code=0
    raw="$(timeout "$(_dispatch_medium_timeout)" \
        env SLOPGUARD_TYPED_LINT=1 \
        "$tool_bin" --config "$config" --format json --no-warn-ignored \
        "$file" 2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local typed_mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/eslint-typed.yaml"
    local common_mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/eslint.yaml"

    local rule_id msg line endline ap_id severity category cwe_str cwe_json fix snippet lookup
    while IFS=$'\t' read -r rule_id msg line endline; do
        [ -n "$rule_id" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        # Try typed-specific mapping first, then common ESLint mapping.
        lookup="$(_dispatch_map_lookup "$typed_mapping" "$rule_id")"
        [ -z "$lookup" ] && lookup="$(_dispatch_map_lookup "$common_mapping" "$rule_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-TS-LINT-000"
            category="maintainability"
            severity="$(_dispatch_default_severity "$category")"
            cwe_json='[]'
        fi
        fix=""
        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "eslint-typed" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "${endline:-$line}" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.[] | .messages[] |
            [.ruleId // "unknown", .message,
             (.line|tostring), ((.endLine // .line)|tostring)] | @tsv' \
        2>/dev/null || true)"
}

# _dispatch_run_tflint  file session_id agent_id project_dir
#                        is_untracked changed_ranges findings_out
_dispatch_run_tflint() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool tflint 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" tflint; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" tflint
            printf 'slopguard: tflint unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path tflint "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode tflint "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local file_dir; file_dir="$(dirname "$file")"

    local raw exit_code=0
    raw="$(timeout "$(_dispatch_medium_timeout)" \
        env TFLINT_PLUGIN_DIR="${SLOPGUARD_CACHE_DIR:-${CLAUDE_PLUGIN_DATA}/cache}/tflint" \
        "$tool_bin" --config "$config" --format json --chdir "$file_dir" \
        2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/tflint.yaml"

    local rule_id msg line ap_id severity category cwe_str cwe_json fix snippet lookup
    while IFS=$'\t' read -r rule_id msg line; do
        [ -n "$rule_id" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        lookup="$(_dispatch_map_lookup "$mapping" "$rule_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-TF-LINT-000"
            category="security"
            severity="$(_dispatch_default_severity "$category")"
            cwe_json='[]'
        fi
        fix=""
        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "tflint" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$line" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.issues[]? |
            [.rule.name, .message, (.range.start.line|tostring)] | @tsv' \
        2>/dev/null || true)"
}

# _dispatch_run_checkov  file session_id agent_id project_dir
#                         is_untracked changed_ranges findings_out
# Runs per-file (tier M); tier S runs --dir (StopGate, Etap 4).
_dispatch_run_checkov() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool checkov 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" checkov; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" checkov
            printf 'slopguard: checkov unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local config; config="$(tool_config_path checkov "$project_dir")"
    local config_mode; config_mode="$(tool_config_mode checkov "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    local raw exit_code=0
    raw="$(timeout "$(_dispatch_medium_timeout)" \
        "$tool_bin" --config-file "$config" -f "$file" 2>/dev/null)" || exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/checkov.yaml"

    local check_id check_name line ap_id severity category cwe_str cwe_json fix snippet lookup
    while IFS=$'\t' read -r check_id check_name line; do
        [ -n "$check_id" ] || continue
        snippet="$(printf '%s' "$check_name" | head -c 120)"
        lookup="$(_dispatch_map_lookup "$mapping" "$check_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            ap_id="AP-IAC-SEC-000"
            category="security"
            severity="$(_dispatch_default_severity "$category")"
            cwe_json='[]'
        fi
        fix=""
        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "checkov" "$check_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$line" "$check_name" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '(if type == "array" then .[] else . end) |
            .results.failed_checks[]? |
            [.check_id, .check_name,
             ((.file_line_range[0] // 0)|tostring)] | @tsv' \
        2>/dev/null || true)"
}

# _dispatch_run_opengrep  file session_id agent_id project_dir
#                          is_untracked changed_ranges findings_out
# Multi-language SAST via Opengrep (§6.11, tier M).
# Uses plugin rules from rules/opengrep/ plus optional project extensions
# (ext_opengrep_rules from lib/ext.sh when sourced).
_dispatch_run_opengrep() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="$4"
    local is_untracked="$5" changed_ranges="$6" findings_out="$7"

    local tool_bin; tool_bin="$(CLAUDE_PROJECT_DIR="$project_dir" resolve_tool opengrep 2>/dev/null || true)"
    if [ -z "$tool_bin" ]; then
        if ! _dispatch_tool_unavail_seen "$session_id" "$agent_id" opengrep; then
            _dispatch_tool_unavail_mark "$session_id" "$agent_id" opengrep
            printf 'slopguard: opengrep unavailable — run: slopguard doctor --install\n' >&2
        fi
        return 0
    fi

    local rules_dir="${CLAUDE_PLUGIN_ROOT}/rules/opengrep"
    local config_mode; config_mode="$(tool_config_mode opengrep "$project_dir")"
    [ "$config_mode" = "skip" ] && return 0
    [ -d "$rules_dir" ] || return 0

    # Optional project-local rules from .slopguard/opengrep/ (ext.sh §7.8).
    local extra_rules=""
    if declare -f ext_opengrep_rules >/dev/null 2>&1; then
        extra_rules="$(ext_opengrep_rules "$project_dir" 2>/dev/null || true)"
    fi

    local raw exit_code=0
    # shellcheck disable=SC2086  # extra_rules intentional word-split
    raw="$(timeout "$(_dispatch_medium_timeout)" \
        "$tool_bin" scan \
        --config "$rules_dir" \
        ${extra_rules:+--config "$extra_rules"} \
        --json --metrics=off --quiet \
        "$file" 2>/dev/null)" || exit_code=$?
    # 0 = no findings, 1 = findings found; others = tool error → fail-open.
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ] || return 0
    [ -n "$raw" ] || return 0

    local mapping="${CLAUDE_PLUGIN_ROOT}/rules/mapping/opengrep.yaml"

    local rule_id msg line meta_ap ap_id severity category cwe_str cwe_json fix snippet lookup
    while IFS=$'\t' read -r rule_id msg line meta_ap; do
        [ -n "$rule_id" ] || continue
        snippet="$(printf '%s' "$msg" | head -c 120)"
        lookup="$(_dispatch_map_lookup "$mapping" "$rule_id")"
        if [ -n "$lookup" ]; then
            IFS=$'\t' read -r ap_id severity category cwe_str <<< "$lookup"
            cwe_json="$(_dispatch_cwe_json "$cwe_str")"
        else
            # Use ap_id from rule metadata when present (§6.11 extra.metadata.ap_id).
            ap_id="${meta_ap:-}"
            category="security"
            severity="error"
            cwe_json='[]'
        fi
        fix=""
        _dispatch_config_filter_emit "$config_mode" \
            "$session_id" "$agent_id" "$ap_id" "opengrep" "$rule_id" \
            "$category" "$severity" "$cwe_json" \
            "$file" "$line" "$line" "$msg" "$fix" "$snippet" \
            "$is_untracked" "$changed_ranges" "$findings_out"
    done <<< "$(printf '%s\n' "$raw" \
        | jq -r '.results[]? |
            [.check_id, .extra.message, (.start.line|tostring),
             (.extra.metadata.ap_id // "")] | @tsv' \
        2>/dev/null || true)"
}

# --------------------------------------------------------------------------- #
# Medium-tier tool selection
# --------------------------------------------------------------------------- #

# _dispatch_medium_tools_for_file <file>
# Print space-separated list of medium-tier tools applicable to this file.
_dispatch_medium_tools_for_file() {
    local file="$1"
    local filename="${file##*/}"
    local ext="${filename##*.}"
    local tools=""

    # PHP → PHPStan + Opengrep SAST
    case "$ext" in
        php) tools="${tools} phpstan opengrep" ;;
    esac

    # Go → golangci-lint (package-scoped) + Opengrep SAST
    case "$ext" in
        go) tools="${tools} golangci_lint opengrep" ;;
    esac

    # TypeScript only → ESLint with type-info + Opengrep SAST
    case "$ext" in
        ts|tsx|mts|cts) tools="${tools} eslint_typed opengrep" ;;
    esac

    # Python → Opengrep SAST (Pyright blocked on Etap 0 pinning)
    case "$ext" in
        py) tools="${tools} opengrep" ;;
    esac

    # JS / JSX → Opengrep SAST
    case "$ext" in
        js|jsx|mjs|cjs) tools="${tools} opengrep" ;;
    esac

    # Terraform → tflint + Checkov
    case "$ext" in
        tf|tofu) tools="${tools} tflint checkov" ;;
    esac

    # Dockerfile → Checkov
    case "$filename" in
        Dockerfile|*.dockerfile|Dockerfile.*)
            case "$tools" in *checkov*) ;; *) tools="${tools} checkov" ;; esac ;;
    esac
    case "$file" in
        */Dockerfile|*/Dockerfile.*)
            case "$tools" in *checkov*) ;; *) tools="${tools} checkov" ;; esac ;;
    esac

    # YAML: GitHub Actions or K8s manifests → Checkov
    case "$ext" in
        yaml|yml)
            case "$tools" in *checkov*) ;;
            *)
                case "$file" in
                    */.github/workflows/*.yml|*/.github/workflows/*.yaml|\
                    .github/workflows/*.yml|.github/workflows/*.yaml)
                        tools="${tools} checkov" ;;
                    *)
                        if [ -f "$file" ] \
                            && grep -q 'apiVersion:' "$file" 2>/dev/null \
                            && grep -q 'kind:' "$file" 2>/dev/null; then
                            tools="${tools} checkov"
                        fi
                        ;;
                esac
                ;;
            esac ;;
    esac

    printf '%s' "${tools# }"
}

# --------------------------------------------------------------------------- #
# Public entry point — medium tier
# --------------------------------------------------------------------------- #

# dispatch_medium <file> <session_id> <agent_id> <project_dir> <findings_out>
#
# Debounces rapid edits (SLOPGUARD_MEDIUM_DEBOUNCE, default 3 s), then runs
# medium-tier tools.  Writes new findings as NDJSON to <findings_out>.
# Always exits 0 (fail-open, §2 Z6).
#
# Dedup via _dispatch_fingerprint_seen means repeat findings are not emitted;
# callers check severity to decide whether to wake the agent (§11.3: only
# new findings ≥ error trigger asyncRewake).
dispatch_medium() {
    local file="$1" session_id="$2" agent_id="$3" project_dir="${4:-.}"
    local findings_out="$5"

    [ -f "$file" ] || return 0

    # ------------------------------------------------------------------ #
    # Debounce: last caller within the window wins.
    # Write a unique token, sleep the debounce window, re-read.  If the
    # token changed (a later invocation overwrote it), yield without running
    # any tools.  This coalesces rapid edits into one run per file set.
    # ------------------------------------------------------------------ #
    local debounce="${SLOPGUARD_MEDIUM_DEBOUNCE:-3}"
    local pending_key
    pending_key="$(_dispatch_medium_pending_key "$session_id" "$agent_id" "$file")"
    mkdir -p "$(dirname "$pending_key")"
    # Use BASHPID for uniqueness in concurrent subshells; fall back to PID + RANDOM.
    local my_token
    my_token="${BASHPID:-$$}-$(date +%s 2>/dev/null || printf '0')-${RANDOM:-0}"
    local _ptmp; _ptmp="${pending_key}.tmp${BASHPID:-$$}"
    printf '%s' "$my_token" > "$_ptmp" && mv "$_ptmp" "$pending_key" || true
    sleep "$debounce" 2>/dev/null || true
    local current_token; current_token="$(cat "$pending_key" 2>/dev/null || true)"
    [ "$current_token" = "$my_token" ] || return 0

    # ------------------------------------------------------------------ #
    # Dispatcher-level timeout: skip remaining tools if the budget is exceeded.
    # Separate from per-tool timeout (SLOPGUARD_MEDIUM_TOOL_TIMEOUT).
    # ------------------------------------------------------------------ #
    local _mm_start; _mm_start="$(date +%s 2>/dev/null || printf '0')"
    _mm_budget_ok() {
        local _now; _now="$(date +%s 2>/dev/null || printf '0')"
        [ $(( _now - _mm_start )) -lt "${SLOPGUARD_MEDIUM_DISPATCH_TIMEOUT:-55}" ]
    }

    # Diff context (same as fast tier).
    local is_untracked=0
    diff_is_untracked "$file" "$project_dir" 2>/dev/null && is_untracked=1

    local changed_ranges=""
    if [ "$is_untracked" -eq 0 ]; then
        changed_ranges="$(diff_changed_ranges "$file" "$project_dir" 2>/dev/null || true)"
    fi

    # Select and run medium-tier tools within the dispatcher budget.
    local tools; tools="$(_dispatch_medium_tools_for_file "$file")"
    local tool
    for tool in $tools; do
        _mm_budget_ok || break
        local fn="_dispatch_run_${tool}"
        if declare -f "$fn" >/dev/null 2>&1; then
            "$fn" "$file" "$session_id" "$agent_id" "$project_dir" \
                "$is_untracked" "$changed_ranges" "$findings_out" || true
        fi
    done

    return 0
}
