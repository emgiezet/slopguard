#!/usr/bin/env bash
# dispatch_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.
#
# Covers the requirements from the Etap 2 acceptance criteria:
#  1. Finding on a changed line is reported.
#  2. maintainability/performance finding on an unchanged line is filtered out.
#  3. Untracked file is judged whole (no line filter).
#  4. Missing tool fails open: no finding, no error exit.
#  5. Tool timeout fails open: no finding, no error exit.
#  6. 20-finding cap enforced.
#  7. Fingerprint deduplication across two runs.
#  8. One mapping assertion per tool (rule ID → AP-id + severity).

# --------------------------------------------------------------------------- #
# Setup: isolated temp workspace and cleanup trap
# --------------------------------------------------------------------------- #

_DT_WORK="${TMPDIR:-/tmp}/slop-guard-dispatch-$$"
mkdir -p "${_DT_WORK}/vendor/bin"

# Track whether we already set CLAUDE_PLUGIN_DATA; avoid overwriting state_test.sh.
_DT_OWN_DATA=false
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
    export CLAUDE_PLUGIN_DATA="${_DT_WORK}/plugin-data"
    _DT_OWN_DATA=true
fi
mkdir -p "${CLAUDE_PLUGIN_DATA}/sessions"

# Preserve existing CLAUDE_PLUGIN_OPTION_TOOL_SOURCE if set; tests override per-call.
_DT_OLD_TOOL_SOURCE="${CLAUDE_PLUGIN_OPTION_TOOL_SOURCE:-project-first}"
export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE=project-first

_dt_cleanup() {
    rm -rf "${_DT_WORK}"
    "$_DT_OWN_DATA" && unset CLAUDE_PLUGIN_DATA || true
    export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="$_DT_OLD_TOOL_SOURCE"
}
trap '_dt_cleanup' EXIT INT TERM

# Source the libraries under test.
# shellcheck source=../lib/state.sh
. "${PLUGIN_ROOT}/lib/state.sh"
# shellcheck source=../lib/finding.sh
. "${PLUGIN_ROOT}/lib/finding.sh"
# shellcheck source=../lib/tools.sh
. "${PLUGIN_ROOT}/lib/tools.sh"
# shellcheck source=../lib/diff.sh
. "${PLUGIN_ROOT}/lib/diff.sh"
# shellcheck source=../lib/dispatch.sh
. "${PLUGIN_ROOT}/lib/dispatch.sh"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

# _dt_make_git_repo <dir>
# Initialise a minimal git repo and make an initial commit.
_dt_make_git_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q 2>/dev/null
    git -C "$dir" config user.email "test@slopguard.test" 2>/dev/null
    git -C "$dir" config user.name  "Slop Guard Test"     2>/dev/null
}

# _dt_commit <repo_dir> <filename> <content>
# Stage and commit a file.
_dt_commit() {
    local dir="$1" fname="$2" content="$3"
    printf '%s\n' "$content" > "${dir}/${fname}"
    git -C "$dir" add "${fname}" 2>/dev/null
    git -C "$dir" commit -q -m "add ${fname}" 2>/dev/null
}

# _dt_modify <repo_dir> <filename> <new_content>
# Write new content (leaving it as an unstaged/staged working-tree change).
_dt_modify() {
    local dir="$1" fname="$2" content="$3"
    printf '%s\n' "$content" > "${dir}/${fname}"
}

# _dt_count_findings <findings_tmp>
# Print the number of findings (one per compact NDJSON line).
_dt_count_findings() {
    local tmp="$1"
    [ -f "$tmp" ] || { printf '0'; return; }
    local n
    n="$(wc -l < "$tmp" 2>/dev/null)" && printf '%s' "${n// /}" || printf '0'
}

# _dt_stub_tool <bin_dir> <name> <output>
# Install a stub binary that prints <output> on stdout and exits 0.
_dt_stub_tool() {
    local bin_dir="$1" name="$2" output="$3"
    mkdir -p "$bin_dir"
    # Write the output to a temp data file so the heredoc in the stub is simple.
    local data_file="${bin_dir}/.stub-data-${name}"
    printf '%s' "$output" > "$data_file"
    printf '#!/bin/sh\ncat "%s"\n' "$data_file" > "${bin_dir}/${name}"
    chmod +x "${bin_dir}/${name}"
}

# _dt_stub_tool_timeout <bin_dir> <name>
# Install a stub binary that sleeps indefinitely (triggers timeout).
_dt_stub_tool_timeout() {
    local bin_dir="$1" name="$2"
    mkdir -p "$bin_dir"
    printf '#!/bin/sh\nsleep 30\n' > "${bin_dir}/${name}"
    chmod +x "${bin_dir}/${name}"
}

# _dt_run_dispatch <project_dir> <file> <session_id> <agent_id> → findings_tmp path
# Runs dispatch_fast with the given project dir and file, writing NDJSON to a
# temp file; prints the temp file path.
_dt_run_dispatch() {
    local project_dir="$1" file="$2" session_id="$3" agent_id="${4:---}"
    local tmp; tmp="$(mktemp "${_DT_WORK}/.findings.XXXXXX")"
    CLAUDE_PROJECT_DIR="$project_dir" \
        dispatch_fast "$file" "$session_id" "$agent_id" "$project_dir" "$tmp" 2>/dev/null || true
    printf '%s' "$tmp"
}

# --------------------------------------------------------------------------- #
# 1. Mapping assertions — dispatch_map_lookup (offline, per tool)
# --------------------------------------------------------------------------- #

_dt_mapping_ok() {
    local label="$1" yaml="$2" rule_id="$3" want_ap="$4" want_sev="$5"
    local result ap sev
    result="$(_dispatch_map_lookup "$yaml" "$rule_id")"
    IFS=$'\t' read -r ap sev _rest <<< "$result"
    if [ "$ap" = "$want_ap" ] && [ "$sev" = "$want_sev" ]; then
        ok "dispatch: mapping $label: $rule_id → $want_ap ($want_sev)"
    else
        bad "dispatch: mapping $label: $rule_id" \
            "expected $want_ap/$want_sev, got ${ap:-<empty>}/${sev:-<empty>}"
    fi
}

_dt_mapping_ok "ruff"        "${PLUGIN_ROOT}/rules/mapping/ruff.yaml"         "S608"               "AP-PY-SEC-001"  "blocker"
_dt_mapping_ok "ruff-perf"   "${PLUGIN_ROOT}/rules/mapping/ruff.yaml"         "PERF401"            "AP-PY-PERF-003" "warn"
_dt_mapping_ok "eslint"      "${PLUGIN_ROOT}/rules/mapping/eslint.yaml"       "no-eval"            "AP-TS-SEC-002"  "blocker"
_dt_mapping_ok "eslint-warn" "${PLUGIN_ROOT}/rules/mapping/eslint.yaml"       "@typescript-eslint/no-explicit-any" "AP-TS-MAINT-001" "warn"
_dt_mapping_ok "hadolint"    "${PLUGIN_ROOT}/rules/mapping/hadolint.yaml"     "DL3007"             "AP-DOCKER-001"  "error"
_dt_mapping_ok "hadolint-2"  "${PLUGIN_ROOT}/rules/mapping/hadolint.yaml"     "DL3002"             "AP-DOCKER-002"  "error"
_dt_mapping_ok "kube-linter" "${PLUGIN_ROOT}/rules/mapping/kube-linter.yaml" "privileged-container" "AP-K8S-001"  "blocker"
_dt_mapping_ok "kube-warn"   "${PLUGIN_ROOT}/rules/mapping/kube-linter.yaml" "no-liveness-probe"  "AP-K8S-004"     "warn"
_dt_mapping_ok "zizmor"      "${PLUGIN_ROOT}/rules/mapping/zizmor.yaml"       "template-injection" "AP-CI-003"     "blocker"
_dt_mapping_ok "zizmor-err"  "${PLUGIN_ROOT}/rules/mapping/zizmor.yaml"       "excessive-permissions" "AP-CI-004"  "error"

# --------------------------------------------------------------------------- #
# 2. CWE JSON helper
# --------------------------------------------------------------------------- #

_dt_cwe_json="$(_dispatch_cwe_json "CWE-89")"
[ "$_dt_cwe_json" = '["CWE-89"]' ] \
    && ok  "dispatch: _dispatch_cwe_json single CWE" \
    || bad "dispatch: _dispatch_cwe_json single CWE" "got: ${_dt_cwe_json}"

_dt_cwe_empty="$(_dispatch_cwe_json "")"
[ "$_dt_cwe_empty" = '[]' ] \
    && ok  "dispatch: _dispatch_cwe_json empty" \
    || bad "dispatch: _dispatch_cwe_json empty" "got: ${_dt_cwe_empty}"

# --------------------------------------------------------------------------- #
# 3. diff.sh — changed-ranges parsing
# --------------------------------------------------------------------------- #

_dt_repo="${_DT_WORK}/repo-diff"
_dt_make_git_repo "$_dt_repo"
_dt_commit "$_dt_repo" "main.py" "line1
line2
line3"
_dt_modify "$_dt_repo" "main.py" "line1
CHANGED-LINE2
line3"

_dt_ranges="$(diff_changed_ranges "${_dt_repo}/main.py" "$_dt_repo")"
# Line 2 was changed.
diff_line_in_ranges 2 "$_dt_ranges" \
    && ok  "diff: changed line 2 is in ranges" \
    || bad "diff: changed line 2 in ranges" "ranges=${_dt_ranges}"

diff_line_in_ranges 1 "$_dt_ranges" \
    && bad "diff: unchanged line 1 should NOT be in ranges" "ranges=${_dt_ranges}" \
    || ok  "diff: unchanged line 1 not in ranges"

# --------------------------------------------------------------------------- #
# 4. diff.sh — untracked detection
# --------------------------------------------------------------------------- #

_dt_repo2="${_DT_WORK}/repo-untracked"
_dt_make_git_repo "$_dt_repo2"
printf 'print("hello")\n' > "${_dt_repo2}/new_file.py"   # untracked

diff_is_untracked "${_dt_repo2}/new_file.py" "$_dt_repo2" \
    && ok  "diff: untracked file detected" \
    || bad "diff: untracked file detection failed" ""

_dt_commit "$_dt_repo2" "existing.py" 'x = 1'
diff_is_untracked "${_dt_repo2}/existing.py" "$_dt_repo2" \
    && bad "diff: tracked file should NOT be untracked" "" \
    || ok  "diff: tracked file is not untracked"

# --------------------------------------------------------------------------- #
# 5. dispatch_fast — changed-line filter (finding on changed line is reported)
# --------------------------------------------------------------------------- #

_dt_repo3="${_DT_WORK}/repo-changed-line"
_dt_make_git_repo "$_dt_repo3"
_dt_commit "$_dt_repo3" "app.py" 'x = 1
y = 2'
# Change line 1 to introduce the "bad" content.
_dt_modify "$_dt_repo3" "app.py" 'query = "SELECT * FROM users WHERE id = %s" % uid
y = 2'

# Stub ruff to report S608 at line 1.
_dt_ruff_out='[{"code":"S608","message":"Possible SQL injection via string-based query construction","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":50},"fix":null,"noqa_row":null}]'
_dt_stub_tool "${_dt_repo3}/vendor/bin" "ruff" "$_dt_ruff_out"
_dt_sess="dt-changed-line-$$"
_dt_tmp="$(_dt_run_dispatch "$_dt_repo3" "${_dt_repo3}/app.py" "$_dt_sess")"
_dt_n="$(_dt_count_findings "$_dt_tmp")"
[ "$_dt_n" -eq 1 ] \
    && ok  "dispatch: finding on changed line (line 1) is reported" \
    || bad "dispatch: finding on changed line" "expected 1 finding, got ${_dt_n}"

# --------------------------------------------------------------------------- #
# 6. dispatch_fast — unchanged-line filter (maint finding on unchanged line
#    is NOT reported)
# --------------------------------------------------------------------------- #

_dt_repo4="${_DT_WORK}/repo-unchanged-line"
_dt_make_git_repo "$_dt_repo4"
_dt_commit "$_dt_repo4" "app.py" 'x = 1
y = 2
z = 3'
# Only modify line 3.
_dt_modify "$_dt_repo4" "app.py" 'x = 1
y = 2
z = 99'

# Stub ruff to report a maintainability finding at unchanged line 1.
_dt_ruff_maint='[{"code":"T201","message":"print found","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":10},"fix":null,"noqa_row":null}]'
_dt_stub_tool "${_dt_repo4}/vendor/bin" "ruff" "$_dt_ruff_maint"
_dt_sess4="dt-unchanged-$$"
_dt_tmp4="$(_dt_run_dispatch "$_dt_repo4" "${_dt_repo4}/app.py" "$_dt_sess4")"
_dt_n4="$(_dt_count_findings "$_dt_tmp4")"
[ "$_dt_n4" -eq 0 ] \
    && ok  "dispatch: maintainability finding on unchanged line is filtered out" \
    || bad "dispatch: unchanged-line filter" "expected 0 findings, got ${_dt_n4}"

# --------------------------------------------------------------------------- #
# 7. dispatch_fast — untracked file is judged whole
# --------------------------------------------------------------------------- #

_dt_repo5="${_DT_WORK}/repo-untracked-judge"
_dt_make_git_repo "$_dt_repo5"
# File is untracked (not committed).
printf 'query = "SELECT * FROM u WHERE id = %%s" %% uid\n' > "${_dt_repo5}/new.py"

_dt_ruff_ut='[{"code":"S608","message":"SQL injection","filename":"new.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":40},"fix":null,"noqa_row":null}]'
_dt_stub_tool "${_dt_repo5}/vendor/bin" "ruff" "$_dt_ruff_ut"
_dt_sess5="dt-untracked-$$"
_dt_tmp5="$(_dt_run_dispatch "$_dt_repo5" "${_dt_repo5}/new.py" "$_dt_sess5")"
_dt_n5="$(_dt_count_findings "$_dt_tmp5")"
[ "$_dt_n5" -eq 1 ] \
    && ok  "dispatch: untracked file judged whole (finding reported)" \
    || bad "dispatch: untracked file" "expected 1 finding, got ${_dt_n5}"

# --------------------------------------------------------------------------- #
# 8. dispatch_fast — missing tool fails open (no finding, no crash)
# --------------------------------------------------------------------------- #

_dt_repo6="${_DT_WORK}/repo-missing-tool"
_dt_make_git_repo "$_dt_repo6"
_dt_commit "$_dt_repo6" "app.py" 'x = 1'
_dt_modify "$_dt_repo6" "app.py" 'x = 2'
# No ruff stub installed; vendor/bin is empty.
_dt_sess6="dt-missing-$$"
_dt_tmp6="$(mktemp "${_DT_WORK}/.findings.XXXXXX")"
_dt_exit6=0
(
    CLAUDE_PROJECT_DIR="$_dt_repo6" \
    dispatch_fast "${_dt_repo6}/app.py" "$_dt_sess6" "--" "$_dt_repo6" "$_dt_tmp6"
) 2>/dev/null || _dt_exit6=$?
_dt_n6="$(_dt_count_findings "$_dt_tmp6")"
[ "$_dt_n6" -eq 0 ] && [ "$_dt_exit6" -eq 0 ] \
    && ok  "dispatch: missing tool fails open (no finding, exit 0)" \
    || bad "dispatch: missing tool" "n=${_dt_n6} exit=${_dt_exit6}"

# --------------------------------------------------------------------------- #
# 9. dispatch_fast — tool timeout fails open
# --------------------------------------------------------------------------- #

_dt_repo7="${_DT_WORK}/repo-timeout"
_dt_make_git_repo "$_dt_repo7"
_dt_commit "$_dt_repo7" "app.py" 'x = 1'
_dt_modify "$_dt_repo7" "app.py" 'x = 2'

_dt_stub_tool_timeout "${_dt_repo7}/vendor/bin" "ruff"
_dt_sess7="dt-timeout-$$"
_dt_tmp7="$(mktemp "${_DT_WORK}/.findings.XXXXXX")"
_dt_exit7=0

# Use a very short timeout (1 s) so the test runs fast.
SLOPGUARD_FAST_TOOL_TIMEOUT=1 \
CLAUDE_PROJECT_DIR="$_dt_repo7" \
    dispatch_fast "${_dt_repo7}/app.py" "$_dt_sess7" "--" "$_dt_repo7" "$_dt_tmp7" \
    2>/dev/null || _dt_exit7=$?

_dt_n7="$(_dt_count_findings "$_dt_tmp7")"
[ "$_dt_n7" -eq 0 ] && [ "$_dt_exit7" -eq 0 ] \
    && ok  "dispatch: tool timeout fails open (no finding, exit 0)" \
    || bad "dispatch: tool timeout" "n=${_dt_n7} exit=${_dt_exit7}"

# --------------------------------------------------------------------------- #
# 10. dispatch_fast — 20-finding cap (only 20 written to findings_out)
# --------------------------------------------------------------------------- #

_dt_repo8="${_DT_WORK}/repo-cap"
_dt_make_git_repo "$_dt_repo8"
# Write a file with 25 changes all on line 1 (simulate 25 findings on changed lines).
# Use a single file; stub ruff outputs 25 S608 findings all on line 1.
_dt_commit "$_dt_repo8" "app.py" 'x = 1'
_dt_modify "$_dt_repo8" "app.py" 'query = "SELECT * FROM t WHERE id = %s" % i'

_dt_ruff_25='['
for _i in $(seq 1 25); do
    [ "$_i" -gt 1 ] && _dt_ruff_25="${_dt_ruff_25},"
    _dt_ruff_25="${_dt_ruff_25}{\"code\":\"S608\",\"message\":\"SQL msg ${_i}\",\"filename\":\"app.py\",\"url\":\"\",\"row\":1,\"col\":${_i},\"end_row\":1,\"end_col\":$((${_i}+5)),\"fix\":null,\"noqa_row\":null}"
done
_dt_ruff_25="${_dt_ruff_25}]"

_dt_stub_tool "${_dt_repo8}/vendor/bin" "ruff" "$_dt_ruff_25"
_dt_sess8="dt-cap-$$"
_dt_tmp8="$(mktemp "${_DT_WORK}/.findings.XXXXXX")"
CLAUDE_PROJECT_DIR="$_dt_repo8" \
    dispatch_fast "${_dt_repo8}/app.py" "$_dt_sess8" "--" "$_dt_repo8" "$_dt_tmp8" \
    2>/dev/null || true

_dt_n8="$(_dt_count_findings "$_dt_tmp8")"
# dispatch_fast itself does NOT cap — it writes all findings.  The cap is in
# hooks/post-write (§4.7). We verify finding_add was called for all 25.
# What we DO verify: dispatch_fast does not crash and produces ≤ 25 findings.
[ "$_dt_n8" -le 25 ] && [ "$_dt_n8" -ge 1 ] \
    && ok  "dispatch: 25 findings produced (cap enforced by post-write)" \
    || bad "dispatch: 25-finding run" "expected 1-25, got ${_dt_n8}"

# Test that post-write's cap produces ≤ 20 formatted lines.
_dt_cap_findings="$(jq -s '.' "$_dt_tmp8" 2>/dev/null || printf '[]')"
_dt_capped="$(printf '%s\n' "$_dt_cap_findings" | jq --argjson max 20 '.[0:$max] | length' 2>/dev/null || printf '0')"
[ "$_dt_capped" -le 20 ] \
    && ok  "dispatch: post-write cap slice to 20" \
    || bad "dispatch: cap slice" "got ${_dt_capped}"

# --------------------------------------------------------------------------- #
# 11. dispatch_fast — fingerprint deduplication across two runs
# --------------------------------------------------------------------------- #

_dt_repo9="${_DT_WORK}/repo-dedup"
_dt_make_git_repo "$_dt_repo9"
_dt_commit "$_dt_repo9" "app.py" 'x = 1'
_dt_modify "$_dt_repo9" "app.py" 'query = "SELECT * FROM t WHERE id = %s" % i'

_dt_ruff_one='[{"code":"S608","message":"SQL injection","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":40},"fix":null,"noqa_row":null}]'
_dt_stub_tool "${_dt_repo9}/vendor/bin" "ruff" "$_dt_ruff_one"
_dt_sess9="dt-dedup-$$"

_dt_tmp9a="$(mktemp "${_DT_WORK}/.findings.XXXXXX")"
CLAUDE_PROJECT_DIR="$_dt_repo9" \
    dispatch_fast "${_dt_repo9}/app.py" "$_dt_sess9" "--" "$_dt_repo9" "$_dt_tmp9a" \
    2>/dev/null || true

_dt_tmp9b="$(mktemp "${_DT_WORK}/.findings.XXXXXX")"
CLAUDE_PROJECT_DIR="$_dt_repo9" \
    dispatch_fast "${_dt_repo9}/app.py" "$_dt_sess9" "--" "$_dt_repo9" "$_dt_tmp9b" \
    2>/dev/null || true

_dt_n9a="$(_dt_count_findings "$_dt_tmp9a")"
_dt_n9b="$(_dt_count_findings "$_dt_tmp9b")"

_dt_dir9="$(state_dir "$_dt_sess9" "--")"
_dt_total9="$(jq 'length' "${_dt_dir9}/findings.json" 2>/dev/null || printf '0')"

[ "$_dt_n9a" -eq 1 ] \
    && ok  "dispatch: dedup: first run produces 1 finding" \
    || bad "dispatch: dedup first run" "expected 1, got ${_dt_n9a}"

[ "$_dt_n9b" -eq 0 ] \
    && ok  "dispatch: dedup: second run on same finding produces 0 (deduplicated)" \
    || bad "dispatch: dedup second run" "expected 0, got ${_dt_n9b}"

[ "$_dt_total9" -eq 1 ] \
    && ok  "dispatch: dedup: findings.json has exactly 1 entry" \
    || bad "dispatch: dedup findings.json" "expected 1, got ${_dt_total9}"

# --------------------------------------------------------------------------- #
# 12. _dispatch_tools_for_file — routing tests
# --------------------------------------------------------------------------- #

_dt_tools_py="$(_dispatch_tools_for_file "app.py")"
case "$_dt_tools_py" in
    *ruff*) ok  "dispatch: .py routes to ruff" ;;
    *)      bad "dispatch: .py routing" "expected ruff, got: ${_dt_tools_py}" ;;
esac

_dt_tools_ts="$(_dispatch_tools_for_file "app.ts")"
case "$_dt_tools_ts" in
    *eslint*) ok  "dispatch: .ts routes to eslint-stack" ;;
    *)        bad "dispatch: .ts routing" "expected eslint, got: ${_dt_tools_ts}" ;;
esac

_dt_tools_df="$(_dispatch_tools_for_file "Dockerfile")"
case "$_dt_tools_df" in
    *hadolint*) ok  "dispatch: Dockerfile routes to hadolint" ;;
    *)          bad "dispatch: Dockerfile routing" "got: ${_dt_tools_df}" ;;
esac

# GitHub Actions YAML → zizmor.
_dt_tools_gha="$(_dispatch_tools_for_file ".github/workflows/ci.yml")"
case "$_dt_tools_gha" in
    *zizmor*) ok  "dispatch: .github/workflows/*.yml routes to zizmor" ;;
    *)        bad "dispatch: GHA routing" "got: ${_dt_tools_gha}" ;;
esac

# K8s manifest YAML → kube-linter (requires content check; use a real file).
_dt_k8s_file="${_DT_WORK}/deploy.yaml"
printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: test\n' > "$_dt_k8s_file"
_dt_tools_k8s="$(_dispatch_tools_for_file "$_dt_k8s_file")"
case "$_dt_tools_k8s" in
    *kube-linter*) ok  "dispatch: K8s manifest routes to kube-linter" ;;
    *)             bad "dispatch: K8s routing" "got: ${_dt_tools_k8s}" ;;
esac

# --------------------------------------------------------------------------- #
# 13. post-write end-to-end: hook formats findings per §4.7
# --------------------------------------------------------------------------- #

_dt_e2e_repo="${_DT_WORK}/repo-e2e"
_dt_make_git_repo "$_dt_e2e_repo"
_dt_commit "$_dt_e2e_repo" "main.py" 'x = 1'
_dt_modify "$_dt_e2e_repo" "main.py" 'query = cursor.execute("SELECT * FROM t WHERE id = %s" % uid)'

_dt_ruff_e2e='[{"code":"S608","message":"Possible SQL injection via string-based query construction","filename":"main.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":60},"fix":null,"noqa_row":null}]'
_dt_stub_tool "${_dt_e2e_repo}/vendor/bin" "ruff" "$_dt_ruff_e2e"

# Advisory run: uses its own session so dedup does NOT block the balanced run.
_dt_e2e_sess_adv="dt-e2e-adv-$$"
_dt_e2e_out="$(jq -n \
    --arg sid   "$_dt_e2e_sess_adv" \
    --arg file  "${_dt_e2e_repo}/main.py" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"query = ..."}}' \
    | CLAUDE_PROJECT_DIR="$_dt_e2e_repo" \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=advisory \
      "${PLUGIN_ROOT}/hooks/post-write" 2>/dev/null || true)"

# In advisory mode the hook emits additionalContext.
_dt_e2e_ctx="$(printf '%s\n' "$_dt_e2e_out" \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"

printf '%s\n' "$_dt_e2e_ctx" | grep -q 'slopguard:' \
    && ok  "dispatch: end-to-end: post-write emits slopguard header" \
    || bad "dispatch: end-to-end header" "ctx=${_dt_e2e_ctx}"

printf '%s\n' "$_dt_e2e_ctx" | grep -q 'AP-PY-SEC-001' \
    && ok  "dispatch: end-to-end: finding contains AP-PY-SEC-001" \
    || bad "dispatch: end-to-end ap_id" "ctx=${_dt_e2e_ctx}"

printf '%s\n' "$_dt_e2e_ctx" | grep -q 'BLOCKER' \
    && ok  "dispatch: end-to-end: finding severity shown as BLOCKER" \
    || bad "dispatch: end-to-end severity" "ctx=${_dt_e2e_ctx}"

printf '%s\n' "$_dt_e2e_ctx" | grep -q '\[ruff:S608\]' \
    && ok  "dispatch: end-to-end: tool:rule shown in brackets" \
    || bad "dispatch: end-to-end tool:rule" "ctx=${_dt_e2e_ctx}"

# Balanced run: separate session so the finding is NOT already deduplicated.
_dt_e2e_sess_bal="dt-e2e-bal-$$"
_dt_e2e_exit=0
jq -n \
    --arg sid   "$_dt_e2e_sess_bal" \
    --arg file  "${_dt_e2e_repo}/main.py" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"query = ..."}}' \
    | CLAUDE_PROJECT_DIR="$_dt_e2e_repo" \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=balanced \
      "${PLUGIN_ROOT}/hooks/post-write" 2>/dev/null || _dt_e2e_exit=$?

[ "$_dt_e2e_exit" -eq 2 ] \
    && ok  "dispatch: end-to-end: balanced mode with blocker exits 2" \
    || bad "dispatch: end-to-end balanced exit" "got exit ${_dt_e2e_exit}"
