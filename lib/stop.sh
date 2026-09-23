#!/usr/bin/env bash
# lib/stop.sh — Stop gate (§4.4 stop-gate, §11.3 Etap 4).
#
# Entry point: stop_main
# Called by hooks/stop after libs are sourced and hook_input is read.
#
# Checks wired (pinned in tools.lock.json):
#   psalm      — taint analysis; PHP files from session diff; Tainted* filter (§6.1)
#   checkov    — directory scan; IaC dirs from session diff (§6.6)
#   betterleaks — secret scan of git diff HEAD (§6.10)
#   (internal) deps_check_main — dependency freshness; only with ALLOW_NETWORK (§7.7)
#   (internal) docs_seen / docs_recall — AP-AGENT-010 (§7.6)
#
# Not wired — blocked on Etap 0 pinning (absent from tools.lock.json):
#   tsc --noEmit, govulncheck, composer audit, npm audit, pip-audit, osv-scanner
#
# Requires (sourced by hooks/stop before calling stop_main):
#   lib/hook.sh  lib/state.sh  lib/finding.sh  lib/tools.sh
#   lib/docs.sh  lib/secrets.sh

# --------------------------------------------------------------------------- #
# Iteration-counter helpers
# --------------------------------------------------------------------------- #

# _stop_read_iters <dir>  — print current stop-iterations value (0 if absent).
_stop_read_iters() {
    local iter_file="${1}/stop-iterations"
    local raw="0"
    if [ -f "$iter_file" ]; then
        raw="$(cat "$iter_file" 2>/dev/null || printf '0')"
        case "$raw" in [0-9]*) ;; *) raw=0 ;; esac
    fi
    printf '%d' "$raw"
}

# _stop_inc_iterations <dir>  — atomically increment; print new value.
_stop_inc_iterations() {
    local dir="$1"
    local iter_file="${dir}/stop-iterations"
    local iters; iters="$(_stop_read_iters "$dir")"
    local new_iters=$(( iters + 1 ))
    local tmp; tmp="$(mktemp "${dir}/.stop-iters.XXXXXX")"
    printf '%d\n' "$new_iters" > "$tmp" && mv "$tmp" "$iter_file"
    printf '%d' "$new_iters"
}

# --------------------------------------------------------------------------- #
# Changed-file helpers
# --------------------------------------------------------------------------- #

# _stop_diff_files <project_dir>
# Print relative paths of files changed vs HEAD (tracked) and untracked files.
_stop_diff_files() {
    local project_dir="$1"
    local tracked untracked
    tracked="$(cd "$project_dir" && git diff HEAD --name-only 2>/dev/null || true)"
    untracked="$(cd "$project_dir" && git ls-files --others --exclude-standard 2>/dev/null || true)"
    printf '%s\n%s\n' "$tracked" "$untracked"
}

# _stop_iac_dirs <changed_files_str>
# Print unique directories containing changed IaC files.
_stop_iac_dirs() {
    local changed_files="$1"
    local seen=" "
    local f d
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
            *.tf|*.hcl|*.yaml|*.yml|Dockerfile|*/Dockerfile)
                d="$(dirname "$f")"
                case "$seen" in *" ${d} "*) ;; *)
                    seen="${seen}${d} "
                    printf '%s\n' "$d"
                ;; esac
                ;;
        esac
    done <<< "$changed_files"
}

# --------------------------------------------------------------------------- #
# Psalm taint analysis
# --------------------------------------------------------------------------- #

# _stop_run_psalm <session_id> <agent_id> <project_dir> <changed_files>
# Run psalm taint analysis on PHP files in the session diff; add findings.
_stop_run_psalm() {
    local session_id="$1" agent_id="$2" project_dir="$3" changed_files="$4"

    # Only relevant if PHP files were changed.
    local has_php=0
    local f
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in *.php) has_php=1; break ;; esac
    done <<< "$changed_files"
    [ "$has_php" -eq 1 ] || return 0

    # Respect config_source knob: project-only skips psalm even at stop gate.
    # In overlay mode all psalm taint findings are category=security, so the overlay
    # filter is a no-op here — none are silenced.  Verify rather than assume.
    if declare -F tool_config_mode >/dev/null 2>&1; then
        local _psalm_mode; _psalm_mode="$(tool_config_mode psalm "$project_dir")"
        [ "$_psalm_mode" = "skip" ] && return 0
    fi

    # Resolve binary.
    local psalm_bin=""
    if declare -F resolve_tool >/dev/null 2>&1; then
        psalm_bin="$(resolve_tool psalm 2>/dev/null || true)"
    fi
    [ -n "$psalm_bin" ] || psalm_bin="$(command -v psalm 2>/dev/null || true)"
    if [ -z "$psalm_bin" ]; then
        printf 'slopguard: psalm unavailable; taint analysis skipped (fail-open)\n' >&2
        return 0
    fi

    # Locate config: project first, baseline fallback.
    local config=""
    for c in "${project_dir}/psalm.xml" "${project_dir}/psalm.xml.dist"; do
        [ -f "$c" ] && { config="$c"; break; }
    done
    [ -n "$config" ] || config="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}/configs/baseline/psalm.xml"

    # Run psalm; capture output regardless of exit code.
    local psalm_raw=""
    psalm_raw="$("$psalm_bin" \
        --taint-analysis --output-format=json --no-progress \
        ${config:+-c "$config"} 2>/dev/null)" || true
    [ -z "$psalm_raw" ] && return 0

    # Normalise output: accept plain array or wrapped {issues:[…]} / {errors:[…]}.
    local issues_json
    issues_json="$(printf '%s' "$psalm_raw" | jq -c \
        'if type == "array" then .
         elif (.issues // null) != null then .issues
         elif (.errors // null) != null then .errors
         else [] end
         | .[] | select(.type | test("^Tainted"; ""))' \
        2>/dev/null || true)"
    [ -z "$issues_json" ] && return 0

    # Build a set of changed PHP basenames for filtering ("|base1|base2|…|").
    local php_basenames="|"
    while IFS= read -r pf; do
        [ -z "$pf" ] && continue
        case "$pf" in *.php)
            php_basenames="${php_basenames}$(basename "$pf")|"
            ;;
        esac
    done <<< "$changed_files"

    # Process each issue line.
    while IFS= read -r issue; do
        [ -z "$issue" ] && continue

        local itype ifile iline iendline imsg isnippet
        itype="$(printf '%s' "$issue" | jq -r '.type // empty' 2>/dev/null)"
        ifile="$(printf '%s' "$issue" | jq -r '.file_path // .file_name // empty' 2>/dev/null)"
        iline="$(printf '%s' "$issue" | jq -r '(.line_from // 0) | tonumber | floor' 2>/dev/null || printf '0')"
        iendline="$(printf '%s' "$issue" | jq -r '(.line_to // .line_from // 0) | tonumber | floor' 2>/dev/null || printf '0')"
        imsg="$(printf '%s' "$issue" | jq -r '.message // empty' 2>/dev/null)"
        isnippet="$(printf '%s' "$issue" | jq -r '.snippet // ""' 2>/dev/null)"

        [ -z "$itype" ] || [ -z "$ifile" ] && continue

        # Filter: finding file must belong to a changed PHP file (basename match).
        local fbase; fbase="$(basename "$ifile")"
        case "$php_basenames" in *"|${fbase}|"*) ;; *) continue ;; esac

        # Map severity per §6.1.
        local severity="error"
        case "$itype" in
            TaintedSql|TaintedShell|TaintedUnserialize|TaintedInclude|TaintedEval)
                severity="blocker" ;;
        esac

        # Map AP-id and CWE per §8.1.
        local ap_id cwe
        case "$itype" in
            TaintedSql)         ap_id="AP-PHP-SEC-001"; cwe='["CWE-89"]'  ;;
            TaintedUnserialize) ap_id="AP-PHP-SEC-002"; cwe='["CWE-502"]' ;;
            TaintedShell)       ap_id="AP-PHP-SEC-003"; cwe='["CWE-78"]'  ;;
            TaintedFile)        ap_id="AP-PHP-SEC-008"; cwe='["CWE-22"]'  ;;
            *)                  ap_id="AP-PHP-SEC-001"; cwe='["CWE-89"]'  ;;
        esac

        finding_add "$session_id" "$agent_id" \
            "$ap_id" "psalm" "$itype" "security" "$severity" "$cwe" \
            "$ifile" "$iline" "$iendline" \
            "${imsg:-Tainted dataflow detected}" \
            "Use parameterized queries or the safe framework API" \
            "changed-lines" "$isnippet"
    done <<< "$issues_json"
}

# --------------------------------------------------------------------------- #
# Checkov directory scan
# --------------------------------------------------------------------------- #

# _stop_checkov_severity <check_id>
# Map Checkov check ID to severity (§6.6).  Reads mapping/checkov.yaml first.
_stop_checkov_severity() {
    local check_id="$1"
    local mapping="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}/rules/mapping/checkov.yaml"
    if [ -f "$mapping" ]; then
        local sev
        sev="$(awk -v id="$check_id" '
            /^rules:/{in_r=1;next}
            in_r && /^  [[:alnum:]]/{cur=$0;gsub(/^  |:.*$/,"",cur)}
            in_r && cur==id && /severity:/{gsub(/.*severity:[[:space:]]*/,"");print;exit}
        ' "$mapping" 2>/dev/null || true)"
        [ -n "$sev" ] && { printf '%s' "$sev"; return; }
    fi
    # Hardcoded defaults per §6.6: public access / missing encryption → blocker.
    case "$check_id" in
        CKV_AWS_18|CKV_AWS_19|CKV_AWS_20|CKV_AWS_21|CKV_AWS_56|CKV_AWS_57|\
        CKV2_AWS_3|CKV2_AWS_6|CKV_GCP_62|CKV_AZURE_33|CKV_AWS_73|CKV_AWS_75)
            printf 'blocker' ;;
        *)  printf 'warn' ;;
    esac
}

# _stop_run_checkov <session_id> <agent_id> <project_dir> <changed_files>
# Run checkov on changed IaC directories; add findings.
_stop_run_checkov() {
    local session_id="$1" agent_id="$2" project_dir="$3" changed_files="$4"

    local iac_dirs; iac_dirs="$(_stop_iac_dirs "$changed_files")"
    [ -n "$iac_dirs" ] || return 0

    # Respect config_source knob: project-only skips checkov even at stop gate.
    # In overlay mode all checkov findings here are category=security, so the overlay
    # filter is a no-op here — none are silenced.  Verify rather than assume.
    if declare -F tool_config_mode >/dev/null 2>&1; then
        local _ckv_mode; _ckv_mode="$(tool_config_mode checkov "$project_dir")"
        [ "$_ckv_mode" = "skip" ] && return 0
    fi

    # Resolve binary.
    local ckv_bin=""
    if declare -F resolve_tool >/dev/null 2>&1; then
        ckv_bin="$(resolve_tool checkov 2>/dev/null || true)"
    fi
    [ -n "$ckv_bin" ] || ckv_bin="$(command -v checkov 2>/dev/null || true)"
    if [ -z "$ckv_bin" ]; then
        printf 'slopguard: checkov unavailable; IaC directory scan skipped (fail-open)\n' >&2
        return 0
    fi

    # Locate config.
    local ckv_config=""
    for c in "${project_dir}/.checkov.yaml" \
              "${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}/configs/baseline/.checkov.yaml"; do
        [ -f "$c" ] && { ckv_config="$c"; break; }
    done

    local dir
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        # Resolve to absolute path.
        local abs_dir="${dir}"
        [ "${abs_dir#/}" = "$abs_dir" ] && abs_dir="${project_dir}/${abs_dir}"
        [ -d "$abs_dir" ] || continue

        local ckv_raw=""
        ckv_raw="$("$ckv_bin" \
            ${ckv_config:+--config-file "$ckv_config"} \
            --output json -d "$abs_dir" 2>/dev/null)" || true
        [ -z "$ckv_raw" ] && continue

        # Capture failed checks (jaq workaround: variable first, then loop).
        local checks_json
        checks_json="$(printf '%s' "$ckv_raw" | jq -c \
            '.results.failed_checks[]? // empty' 2>/dev/null || true)"
        [ -z "$checks_json" ] && continue

        while IFS= read -r chk; do
            [ -z "$chk" ] && continue
            local check_id chk_file line_s line_e chk_resource
            check_id="$(printf '%s' "$chk"   | jq -r '.check_id    // empty'          2>/dev/null)"
            chk_file="$(printf '%s' "$chk"   | jq -r '.file_path   // empty'          2>/dev/null)"
            line_s="$(printf '%s' "$chk"     | jq -r '(.file_line_range[0] // 0) | tonumber | floor' 2>/dev/null || printf '0')"
            line_e="$(printf '%s' "$chk"     | jq -r '(.file_line_range[1] // 0) | tonumber | floor' 2>/dev/null || printf '0')"
            chk_resource="$(printf '%s' "$chk" | jq -r '.resource // ""'              2>/dev/null)"
            [ -z "$check_id" ] && continue

            local severity; severity="$(_stop_checkov_severity "$check_id")"

            finding_add "$session_id" "$agent_id" \
                "AP-IaC-SEC-001" "checkov" "$check_id" "security" "$severity" '[]' \
                "${chk_file:-$abs_dir}" "$line_s" "$line_e" \
                "Checkov ${check_id}${chk_resource:+ (${chk_resource})}" \
                "Review ${check_id} in Checkov documentation" \
                "changed-lines" "${check_id}|${chk_file}"
        done <<< "$checks_json"
    done <<< "$iac_dirs"
}

# --------------------------------------------------------------------------- #
# Secret scan of session diff
# --------------------------------------------------------------------------- #

# _stop_scan_secrets <session_id> <agent_id> <project_dir>
# Pipe git diff HEAD through betterleaks; add blocker finding on match.
_stop_scan_secrets() {
    local session_id="$1" agent_id="$2" project_dir="$3"

    # Resolve scanner (betterleaks preferred, gitleaks fallback).
    local scanner=""
    local s
    for s in betterleaks gitleaks; do
        local sb=""
        if declare -F resolve_tool >/dev/null 2>&1; then
            sb="$(resolve_tool "$s" 2>/dev/null || true)"
        fi
        [ -n "$sb" ] || sb="$(command -v "$s" 2>/dev/null || true)"
        if [ -n "$sb" ]; then
            scanner="$sb"
            break
        fi
    done
    if [ -z "$scanner" ]; then
        printf 'slopguard: betterleaks/gitleaks unavailable; secret scan skipped (fail-open)\n' >&2
        return 0
    fi

    local scan_config=""
    for c in "${project_dir}/.gitleaks.toml" \
              "${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}/configs/baseline/.gitleaks.toml"; do
        [ -f "$c" ] && { scan_config="$c"; break; }
    done

    # Build scan input: tracked diff + untracked file contents (§6.10).
    local scan_input=""
    local tracked_diff=""
    tracked_diff="$(cd "$project_dir" && git diff HEAD 2>/dev/null || true)"
    scan_input="$tracked_diff"

    # Append content of untracked files (omit .git and ignored files).
    local untracked_list=""
    untracked_list="$(cd "$project_dir" && \
        git ls-files --others --exclude-standard 2>/dev/null || true)"
    if [ -n "$untracked_list" ]; then
        local uf uf_content
        while IFS= read -r uf; do
            [ -z "$uf" ] && continue
            uf_content="$(cat "${project_dir}/${uf}" 2>/dev/null || true)"
            [ -z "$uf_content" ] && continue
            scan_input="${scan_input}"$'\n'"# untracked: ${uf}"$'\n'"${uf_content}"
        done <<< "$untracked_list"
    fi

    [ -n "$scan_input" ] || return 0

    local scan_rc=0
    printf '%s' "$scan_input" | \
        "$scanner" stdin \
            ${scan_config:+--config "$scan_config"} \
            --report-format json --report-path - --redact --no-banner \
            >/dev/null 2>&1 || scan_rc=$?

    # Exit code 1 = secret found (per secrets.sh contract).
    if [ "$scan_rc" -eq 1 ]; then
        finding_add "$session_id" "$agent_id" \
            "AP-SEC-001" "betterleaks" "CredentialInDiff" \
            "security" "blocker" '["CWE-798"]' \
            "git diff HEAD" 0 0 \
            "Secret or credential detected in session diff" \
            "Remove the credential and rotate it; use an environment variable or secret manager" \
            "changed-lines" "diff|session"
    fi
}

# --------------------------------------------------------------------------- #
# Dependency freshness (§7.7)
# --------------------------------------------------------------------------- #

# _stop_check_deps <project_dir>
# Source deps.sh and run deps_check_main --json.
# Prints JSON array (empty on failure); callers parse for major-behind/too-fresh.
_stop_check_deps() {
    local project_dir="$1"
    local deps_lib="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}/lib/deps.sh"
    [ -f "$deps_lib" ] || { printf '[]'; return 0; }
    # shellcheck source=../lib/deps.sh
    . "$deps_lib"
    local raw=""
    raw="$(deps_check_main --json "$project_dir" 2>/dev/null || true)"
    printf '%s' "${raw:-[]}"
}

# --------------------------------------------------------------------------- #
# AP-AGENT-010 (§7.6)
# --------------------------------------------------------------------------- #

# _stop_check_docs <session_id> <agent_id> <project_dir> <changed_files>
# Emit a WARN line per framework edited without a Context7 lookup.
# Never produces a deny; never blocks.
_stop_check_docs() {
    local session_id="$1" agent_id="$2" project_dir="$3" changed_files="$4"

    [ "${CLAUDE_PLUGIN_OPTION_REQUIRE_DOCS_LOOKUP:-true}" = "false" ] && return 0

    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    local profile="${dir}/profile.json"
    [ -f "$profile" ] || return 0

    local fwv_json
    fwv_json="$(jq -r '.framework_versions // empty' "$profile" 2>/dev/null || true)"
    [ -z "$fwv_json" ] && return 0

    local stacks_file="${SLOPGUARD_STACKS_JSON:-${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}/rules/stacks.json}"
    [ -f "$stacks_file" ] || return 0

    # Get tags that have context7 and appear in framework_versions.
    local fw_pairs
    fw_pairs="$(jq -r \
        --argjson fwv "$fwv_json" \
        'to_entries
         | map(select(.value.context7 != null and ($fwv[.key] != null)))
         | map("\(.key)|\(.value.context7)|\($fwv[.key])")
         | .[]' \
        "$stacks_file" 2>/dev/null || true)"
    [ -z "$fw_pairs" ] && return 0

    local pair fw_tag fw_query fw_ver
    while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        fw_tag="${pair%%|*}"
        local rest="${pair#*|}"
        fw_query="${rest%%|*}"
        fw_ver="${rest##*|}"

        # Get globs for this framework.
        local globs
        globs="$(jq -r --arg t "$fw_tag" \
            '.[$t].globs[]? // empty' "$stacks_file" 2>/dev/null || true)"
        [ -z "$globs" ] && continue

        # Check if any changed file matches a framework glob.
        local fw_touched=0
        local cf
        while IFS= read -r cf; do
            [ -z "$cf" ] && continue
            local cfbase; cfbase="${cf##*/}"
            local glob
            while IFS= read -r glob; do
                [ -z "$glob" ] && continue
                local pat="${glob##**/}"
                # shellcheck disable=SC2254
                case "$cfbase" in $pat) fw_touched=1; break 2 ;; esac
            done <<< "$globs"
        done <<< "$changed_files"
        [ "$fw_touched" -eq 1 ] || continue

        # Check if a Context7 lookup was recorded.
        if docs_seen "$session_id" "$agent_id" "$fw_query" 2>/dev/null; then
            continue
        fi
        if docs_recall "$fw_query" "$fw_ver" 2>/dev/null; then
            continue
        fi

        # No lookup — warn (NEVER deny, per §11.3 and §7.6).
        printf 'WARN  AP-AGENT-010 [slopguard:docs-lookup-required] %s %s files edited without Context7 lookup. Consult mcp__context7__resolve-library-id("%s") before restructuring framework code.\n' \
            "$fw_tag" "$fw_ver" "$fw_query"
    done <<< "$fw_pairs"
}

# --------------------------------------------------------------------------- #
# Suppression and out-of-hunk counters
# --------------------------------------------------------------------------- #

# _stop_count_suppressions <project_dir>
# Count suppression-marker lines added in git diff HEAD.
_stop_count_suppressions() {
    local project_dir="$1"
    local diff_out=""
    diff_out="$(cd "$project_dir" && git diff HEAD 2>/dev/null || true)"
    [ -n "$diff_out" ] || { printf '0'; return; }
    local count=0
    # grep -c already prints 0 when nothing matches; a `|| printf 0` fallback
    # appends a second value, yielding "0\n0" and breaking every later integer
    # test. Sanitize the captured value instead.
    count="$(printf '%s' "$diff_out" | \
        grep -cE '^\+[^+].+(@phpstan-ignore|@psalm-suppress|//nolint|# noqa|# nosec|# type: ignore|# pyright: ignore|# ty: ignore|eslint-disable|@ts-ignore|@ts-nocheck|@ts-expect-error|checkov:skip=|# tflint-ignore|# hadolint ignore=|# zizmor: ignore|nosemgrep)' \
        2>/dev/null)" || true
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    printf '%s' "$count"
}

# _stop_count_out_of_hunk <project_dir> <findings_json>
# Count added lines in git diff HEAD that are outside finding line ranges.
_stop_count_out_of_hunk() {
    local project_dir="$1" findings_json="$2"
    local diff_out=""
    diff_out="$(cd "$project_dir" && git diff HEAD 2>/dev/null || true)"
    [ -n "$diff_out" ] || { printf '0'; return; }

    local total_added=0
    total_added="$(printf '%s' "$diff_out" | grep -c '^+[^+]' 2>/dev/null)" || true
    case "$total_added" in ''|*[!0-9]*) total_added=0 ;; esac
    [ "$total_added" -gt 0 ] || { printf '0'; return; }

    # Sum line ranges covered by findings.
    local finding_lines=0
    finding_lines="$(printf '%s' "$findings_json" | jq '
        [.[] | select(.line > 0) |
         ((if .end_line > .line then .end_line else .line end) - .line + 1)
        ] | add // 0' 2>/dev/null || printf '0')"

    local out=$(( total_added - finding_lines ))
    [ "$out" -lt 0 ] && out=0
    printf '%d' "$out"
}

# --------------------------------------------------------------------------- #
# Report formatting
# --------------------------------------------------------------------------- #

# _stop_format_report <n_blocker> <n_error> <n_warn> <n_suppress> <n_out>
#                     <findings_json> <dep_notes> <docs_warn>
_stop_format_report() {
    local n_blocker="$1" n_error="$2" n_warn="$3"
    local n_suppress="$4" n_out="$5"
    local findings_json="$6" dep_notes="$7" docs_warn="$8"

    # Summary header.
    local parts=""
    [ "$n_blocker" -gt 0 ] && \
        parts="${parts}${n_blocker} blocker$([ "$n_blocker" -ne 1 ] && printf 's'), "
    [ "$n_error"   -gt 0 ] && \
        parts="${parts}${n_error} error$([ "$n_error" -ne 1 ] && printf 's'), "
    [ "$n_warn"    -gt 0 ] && \
        parts="${parts}${n_warn} warning$([ "$n_warn" -ne 1 ] && printf 's'), "
    parts="${parts%, }"
    [ -z "$parts" ] && parts="no unresolved findings"

    local report="slopguard stop-gate: ${parts}"
    if [ "$n_suppress" -gt 0 ]; then
        report="${report} — ${n_suppress} suppression$([ "$n_suppress" -ne 1 ] && printf 's') added this session"
    fi
    if [ "$n_out" -gt 0 ]; then
        report="${report} — ${n_out} out-of-hunk line$([ "$n_out" -ne 1 ] && printf 's') changed"
    fi

    # Per-file finding lines (§4.7 format; cap at 20).
    if [ "$(( n_blocker + n_error + n_warn ))" -gt 0 ]; then
        local body
        body="$(printf '%s' "$findings_json" | jq -r '
            [.[] | select(.severity != "info" and .scope != "pre-existing")] |
            .[0:20] |
            group_by(.file)[] |
            (.[0].file) + "\n" +
            (map(
                "  " +
                (if .severity == "blocker" then "BLOCKER"
                 elif .severity == "error" then "ERROR  "
                 elif .severity == "warn"  then "WARN   "
                 else "INFO   " end) + " " +
                (if .line > 0 then "L\(.line) " else "" end) +
                .ap_id + " " +
                (if (.cwe | length) > 0 then .cwe[0] + " " else "" end) +
                "[\(.tool):\(.tool_rule)] " +
                .message +
                (if .fix != "" then ". Fix: " + .fix else "" end)
            ) | join("\n"))
        ' 2>/dev/null || true)"
        [ -n "$body" ] && report="${report}"$'\n'"${body}"
    fi

    [ -n "$dep_notes" ]  && report="${report}"$'\n'"${dep_notes}"
    [ -n "$docs_warn" ]  && report="${report}"$'\n'"${docs_warn}"

    # Hard cap at 4000 chars (§2 Z4).
    if [ "${#report}" -gt 4000 ]; then
        report="${report:0:3990}..."
    fi
    printf '%s' "$report"
}

# --------------------------------------------------------------------------- #
# Main entry point
# --------------------------------------------------------------------------- #

# stop_main — called by hooks/stop after hook_input.
stop_main() {
    local session_id; session_id="$(hook_field .session_id)"
    local agent_id;   agent_id="$(hook_field .agent_id)"
    local stop_active; stop_active="$(hook_field .stop_hook_active)"
    local cwd;        cwd="$(hook_field .cwd)"

    # Missing session_id: infrastructure failure — fail-open.
    [ -n "$session_id" ] || exit 0

    local enforcement="${CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE:-balanced}"
    local project_dir="${CLAUDE_PROJECT_DIR:-${cwd:-.}}"

    # Ensure session directory and state files exist.
    local dir; dir="$(state_dir "$session_id" "${agent_id:-}")"
    state_init "$session_id" "${agent_id:-}" 2>/dev/null || true

    # ---------------------------------------------------------------------- #
    # Loop protection (§2 Z8, §3.2 Stop, D4).
    # stop_hook_active=true means a prior Stop block is active.
    # After ≥ 2 blocked iterations, let through with a user-visible message.
    # ---------------------------------------------------------------------- #
    local iters; iters="$(_stop_read_iters "$dir")"

    if [ "$stop_active" = "true" ] && [ "$iters" -ge 2 ]; then
        hook_message "Slop Guard: stop-gate iteration limit reached (${iters} blocks). Unresolved findings remain — review with: slopguard scan ."
        exit 0
    fi

    # Increment BEFORE running checks so a crash still counts as an iteration.
    _stop_inc_iterations "$dir" >/dev/null

    # ---------------------------------------------------------------------- #
    # Collect session diff.
    # ---------------------------------------------------------------------- #
    local changed_files=""
    changed_files="$(_stop_diff_files "$project_dir")"

    # ---------------------------------------------------------------------- #
    # Slow-tier checks.
    # ---------------------------------------------------------------------- #
    _stop_run_psalm    "$session_id" "${agent_id:-}" "$project_dir" "$changed_files"
    _stop_run_checkov  "$session_id" "${agent_id:-}" "$project_dir" "$changed_files"
    _stop_scan_secrets "$session_id" "${agent_id:-}" "$project_dir"

    # Dependency freshness — only with network (§2 Z7, §7.7).
    local dep_notes=""
    if [ "${CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK:-}" = "true" ]; then
        local dep_json=""
        dep_json="$(_stop_check_deps "$project_dir")"
        if [ -n "$dep_json" ] && [ "$dep_json" != "[]" ]; then
            local dep_lines
            dep_lines="$(printf '%s' "$dep_json" | jq -r '
                .[] | select(.verdict == "major-behind" or .verdict == "too-fresh") |
                if .verdict == "major-behind" then
                    "WARN  AP-AGENT-009 [deps-check:major-behind] \(.package) pinned \(.pinned) is major-behind latest \(.latest)"
                else
                    "NOTE  AP-AGENT-009 [deps-check:too-fresh] \(.package) \(.pinned) published \(.age_days) day(s) ago — below cooldown"
                end' 2>/dev/null || true)"
            dep_notes="$dep_lines"
        fi
    fi

    # AP-AGENT-010 docs check (§7.6).
    local docs_warn=""
    docs_warn="$(_stop_check_docs \
        "$session_id" "${agent_id:-}" "$project_dir" "$changed_files")"

    # ---------------------------------------------------------------------- #
    # Read all session findings (accumulated from fast/medium tiers + stop).
    # ---------------------------------------------------------------------- #
    local findings_file="${dir}/findings.json"
    local all_findings="[]"
    [ -f "$findings_file" ] && \
        all_findings="$(cat "$findings_file" 2>/dev/null || printf '[]')"

    # Count unresolved by severity; exclude pre-existing (Z2) scope.
    local n_blocker n_error n_warn
    n_blocker="$(printf '%s' "$all_findings" | jq \
        '[.[] | select(.severity=="blocker" and .scope!="pre-existing")] | length' \
        2>/dev/null || printf '0')"
    n_error="$(printf '%s' "$all_findings" | jq \
        '[.[] | select(.severity=="error" and .scope!="pre-existing")] | length' \
        2>/dev/null || printf '0')"
    n_warn="$(printf '%s' "$all_findings" | jq \
        '[.[] | select(.severity=="warn" and .scope!="pre-existing")] | length' \
        2>/dev/null || printf '0')"

    # Suppression and out-of-hunk counters.
    local n_suppress n_out
    n_suppress="$(_stop_count_suppressions "$project_dir")"
    n_out="$(_stop_count_out_of_hunk "$project_dir" "$all_findings")"

    # ---------------------------------------------------------------------- #
    # Build report.
    # ---------------------------------------------------------------------- #
    local report
    report="$(_stop_format_report \
        "$n_blocker" "$n_error" "$n_warn" \
        "$n_suppress" "$n_out" \
        "$all_findings" "$dep_notes" "$docs_warn")"

    # ---------------------------------------------------------------------- #
    # Enforce mode (§4.6).
    # advisory:  always context, never block.
    # balanced:  block on blockers only.
    # strict:    block on blockers or errors.
    # ---------------------------------------------------------------------- #
    case "$enforcement" in
        advisory)
            hook_context "$report"
            ;;
        balanced)
            if [ "$n_blocker" -gt 0 ]; then
                printf '%s\n' "$report" >&2
                exit 2
            fi
            hook_context "$report"
            ;;
        strict)
            if [ "$n_blocker" -gt 0 ] || [ "$n_error" -gt 0 ]; then
                printf '%s\n' "$report" >&2
                exit 2
            fi
            hook_context "$report"
            ;;
        *)
            # Unknown mode: fail-open, report as context.
            hook_context "$report"
            ;;
    esac
}
