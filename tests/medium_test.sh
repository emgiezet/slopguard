#!/usr/bin/env bash
# medium_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.
#
# Covers Etap 3 acceptance criteria (§11.3):
#  1. Mapping assertion per wired tool (rule id → AP-id + severity).
#  2. Tool routing per file type.
#  3. Finding below error does not wake agent (no exit 2).
#  4. Same finding twice wakes once (dedup = Z8 loop protection).
#  5. Debounce coalesces two rapid edits into one run.
#  6. Dispatcher timeout fails open.
#  7. Missing tool fails open.
#  8. End-to-end wiring: slopguard post-write --tier=medium produces finding.

# --------------------------------------------------------------------------- #
# Setup: isolated temp workspace
# --------------------------------------------------------------------------- #

_MT_WORK="${TMPDIR:-/tmp}/slop-guard-medium-$$"
mkdir -p "${_MT_WORK}"

_MT_OWN_DATA=false
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
    export CLAUDE_PLUGIN_DATA="${_MT_WORK}/plugin-data"
    _MT_OWN_DATA=true
fi
mkdir -p "${CLAUDE_PLUGIN_DATA}/sessions"

_MT_OLD_TOOL_SOURCE="${CLAUDE_PLUGIN_OPTION_TOOL_SOURCE:-project-first}"
export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE=project-first

_mt_cleanup() {
    rm -rf "${_MT_WORK}"
    "$_MT_OWN_DATA" && unset CLAUDE_PLUGIN_DATA || true
    export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="$_MT_OLD_TOOL_SOURCE"
}
trap '_mt_cleanup' EXIT INT TERM

# Source the libraries under test (same pattern as dispatch_test.sh).
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

# _mt_make_git_repo <dir>
_mt_make_git_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q 2>/dev/null
    git -C "$dir" config user.email "test@slopguard.test" 2>/dev/null
    git -C "$dir" config user.name  "Slop Guard Test"     2>/dev/null
}

# _mt_commit <repo_dir> <filename> <content>
_mt_commit() {
    local dir="$1" fname="$2" content="$3"
    printf '%s\n' "$content" > "${dir}/${fname}"
    git -C "$dir" add "${fname}" 2>/dev/null
    git -C "$dir" commit -q -m "add ${fname}" 2>/dev/null
}

# _mt_stub_tool <bin_dir> <name> <output>
# Install a stub that prints <output> and exits 0.
_mt_stub_tool() {
    local bin_dir="$1" name="$2" output="$3"
    mkdir -p "$bin_dir"
    local data="${bin_dir}/.stub-data-${name}"
    printf '%s' "$output" > "$data"
    printf '#!/bin/sh\ncat "%s"\n' "$data" > "${bin_dir}/${name}"
    chmod +x "${bin_dir}/${name}"
}

# _mt_stub_counting_tool <bin_dir> <name> <output> <counter_file>
# Install a stub that appends 'x' to counter_file before printing output.
_mt_stub_counting_tool() {
    local bin_dir="$1" name="$2" output="$3" counter="$4"
    mkdir -p "$bin_dir"
    local data="${bin_dir}/.stub-data-${name}"
    printf '%s' "$output" > "$data"
    printf '#!/bin/sh\nprintf x >> "%s"\ncat "%s"\n' "$counter" "$data" \
        > "${bin_dir}/${name}"
    chmod +x "${bin_dir}/${name}"
}

# _mt_mapping_ok <label> <yaml> <rule_id> <want_ap> <want_sev>
_mt_mapping_ok() {
    local label="$1" yaml="$2" rule_id="$3" want_ap="$4" want_sev="$5"
    local result ap sev
    result="$(_dispatch_map_lookup "$yaml" "$rule_id")"
    IFS=$'\t' read -r ap sev _rest <<< "$result"
    if [ "$ap" = "$want_ap" ] && [ "$sev" = "$want_sev" ]; then
        ok "medium: mapping $label: $rule_id → $want_ap ($want_sev)"
    else
        bad "medium: mapping $label: $rule_id" \
            "expected $want_ap/$want_sev, got ${ap:-<empty>}/${sev:-<empty>}"
    fi
}

# --------------------------------------------------------------------------- #
# 1. Mapping assertions — one per wired tool
# --------------------------------------------------------------------------- #

_mt_mapping_ok "phpstan"     "${PLUGIN_ROOT}/rules/mapping/phpstan.yaml"       "argument.type"                           "AP-PHP-MAINT-001" "error"
_mt_mapping_ok "phpstan-def" "${PLUGIN_ROOT}/rules/mapping/phpstan.yaml"       "phpstan-error"                           "AP-PHP-MAINT-000" "warn"
_mt_mapping_ok "golangci"    "${PLUGIN_ROOT}/rules/mapping/golangci-lint.yaml" "gosec:G201"                              "AP-GO-SEC-002"    "blocker"
_mt_mapping_ok "golangci-p"  "${PLUGIN_ROOT}/rules/mapping/golangci-lint.yaml" "bodyclose"                               "AP-GO-PERF-001"   "error"
_mt_mapping_ok "eslint-t"    "${PLUGIN_ROOT}/rules/mapping/eslint-typed.yaml"  "@typescript-eslint/no-floating-promises" "AP-TS-ASYNC-001"  "error"
_mt_mapping_ok "tflint"      "${PLUGIN_ROOT}/rules/mapping/tflint.yaml"        "terraform_deprecated_interpolation"      "AP-TF-MAINT-001"  "warn"
_mt_mapping_ok "checkov"     "${PLUGIN_ROOT}/rules/mapping/checkov.yaml"       "CKV_AWS_57"                              "AP-TF-SEC-010"    "blocker"
_mt_mapping_ok "checkov-k8s" "${PLUGIN_ROOT}/rules/mapping/checkov.yaml"       "CKV_K8S_1"                               "AP-K8S-010"       "blocker"

# --------------------------------------------------------------------------- #
# 2. Tool routing — _dispatch_medium_tools_for_file
# --------------------------------------------------------------------------- #

_mt_tools_php="$(_dispatch_medium_tools_for_file "Controller.php")"
case "$_mt_tools_php" in
    *phpstan*) ok "medium: .php routes to phpstan" ;;
    *)         bad "medium: .php routing" "expected phpstan, got: ${_mt_tools_php}" ;;
esac

_mt_tools_go="$(_dispatch_medium_tools_for_file "main.go")"
case "$_mt_tools_go" in
    *golangci*) ok "medium: .go routes to golangci_lint" ;;
    *)          bad "medium: .go routing" "expected golangci, got: ${_mt_tools_go}" ;;
esac

_mt_tools_ts="$(_dispatch_medium_tools_for_file "app.ts")"
case "$_mt_tools_ts" in
    *eslint_typed*) ok "medium: .ts routes to eslint_typed" ;;
    *)              bad "medium: .ts routing" "expected eslint_typed, got: ${_mt_tools_ts}" ;;
esac

_mt_tools_tf="$(_dispatch_medium_tools_for_file "main.tf")"
case "$_mt_tools_tf" in
    *tflint*) ok "medium: .tf routes to tflint" ;;
    *)        bad "medium: .tf routing" "expected tflint, got: ${_mt_tools_tf}" ;;
esac
case "$_mt_tools_tf" in
    *checkov*) ok "medium: .tf also routes to checkov" ;;
    *)         bad "medium: .tf checkov routing" "expected checkov, got: ${_mt_tools_tf}" ;;
esac

# --------------------------------------------------------------------------- #
# 3. Missing tool fails open
# --------------------------------------------------------------------------- #

_mt_repo_missing="${_MT_WORK}/repo-missing-tool"
_mt_make_git_repo "$_mt_repo_missing"
printf '<?php\nfunction foo() {}\n' > "${_mt_repo_missing}/App.php"
# No phpstan stub installed; vendor/bin is absent.
_mt_sess_missing="mt-missing-$$"
_mt_tmp_missing="$(mktemp "${_MT_WORK}/.mt-miss.XXXXXX")"
_mt_exit_missing=0
(
    CLAUDE_PROJECT_DIR="$_mt_repo_missing" \
    dispatch_medium "${_mt_repo_missing}/App.php" "$_mt_sess_missing" "" \
        "$_mt_repo_missing" "$_mt_tmp_missing"
) 2>/dev/null || _mt_exit_missing=$?
_mt_n_missing=0
[ -s "$_mt_tmp_missing" ] && _mt_n_missing="$(wc -l < "$_mt_tmp_missing" | tr -d ' ')"
[ "$_mt_n_missing" -eq 0 ] && [ "$_mt_exit_missing" -eq 0 ] \
    && ok "medium: missing tool fails open (no finding, exit 0)" \
    || bad "medium: missing tool" "n=${_mt_n_missing} exit=${_mt_exit_missing}"

# --------------------------------------------------------------------------- #
# 4. Dispatcher timeout fails open (SLOPGUARD_MEDIUM_DISPATCH_TIMEOUT=0)
# --------------------------------------------------------------------------- #

_mt_repo_timeout="${_MT_WORK}/repo-disp-timeout"
_mt_make_git_repo "$_mt_repo_timeout"
printf '<?php\nfunction bar() {}\n' > "${_mt_repo_timeout}/Bar.php"
# Install a phpstan stub that would emit a finding if called.
_mt_phpstan_error_out='{"totals":{"file_errors":1,"other_errors":0},"files":{"x":{"errors":1,"messages":[{"message":"Param mismatch","line":2,"ignorable":true,"identifier":"argument.type"}]}},"errors":[]}'
_mt_stub_tool "${_mt_repo_timeout}/vendor/bin" "phpstan" "$_mt_phpstan_error_out"

_mt_sess_timeout="mt-disp-timeout-$$"
_mt_tmp_timeout="$(mktemp "${_MT_WORK}/.mt-dt.XXXXXX")"
_mt_exit_timeout=0
(
    SLOPGUARD_MEDIUM_DEBOUNCE=0 \
    SLOPGUARD_MEDIUM_DISPATCH_TIMEOUT=0 \
    CLAUDE_PROJECT_DIR="$_mt_repo_timeout" \
    dispatch_medium "${_mt_repo_timeout}/Bar.php" "$_mt_sess_timeout" "" \
        "$_mt_repo_timeout" "$_mt_tmp_timeout"
) 2>/dev/null || _mt_exit_timeout=$?
_mt_n_timeout=0
[ -s "$_mt_tmp_timeout" ] && _mt_n_timeout="$(wc -l < "$_mt_tmp_timeout" | tr -d ' ')"
[ "$_mt_n_timeout" -eq 0 ] && [ "$_mt_exit_timeout" -eq 0 ] \
    && ok "medium: dispatcher timeout (=0) fails open (no finding, exit 0)" \
    || bad "medium: dispatcher timeout" "n=${_mt_n_timeout} exit=${_mt_exit_timeout}"

# --------------------------------------------------------------------------- #
# 5. Finding below error (warn) does not wake agent
# --------------------------------------------------------------------------- #
# missingType.return → AP-PHP-MAINT-003, warn — must NOT produce exit 2.

_mt_repo_warn="${_MT_WORK}/repo-warn"
_mt_make_git_repo "$_mt_repo_warn"
printf '<?php\nfunction baz() {}\n' > "${_mt_repo_warn}/Baz.php"
_mt_phpstan_warn_out='{"totals":{"file_errors":1,"other_errors":0},"files":{"x":{"errors":1,"messages":[{"message":"Method has no return type.","line":2,"ignorable":true,"identifier":"missingType.return"}]}},"errors":[]}'
_mt_stub_tool "${_mt_repo_warn}/vendor/bin" "phpstan" "$_mt_phpstan_warn_out"

_mt_sess_warn="mt-warn-$$"
_mt_warn_stderr="$(mktemp "${_MT_WORK}/.mt-warn-stderr.XXXXXX")"
_mt_exit_warn=0
jq -n \
    --arg sid "$_mt_sess_warn" \
    --arg file "${_mt_repo_warn}/Baz.php" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"<?php\n"}}' \
    | CLAUDE_PROJECT_DIR="$_mt_repo_warn" \
      SLOPGUARD_MEDIUM_DEBOUNCE=0 \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=balanced \
      "${PLUGIN_ROOT}/bin/slopguard" post-write --tier=medium \
      2>"$_mt_warn_stderr" || _mt_exit_warn=$?
[ "$_mt_exit_warn" -eq 0 ] \
    && ok "medium: warn-only finding does not wake agent (exit 0)" \
    || bad "medium: warn-only exit" "expected 0, got ${_mt_exit_warn}"

# --------------------------------------------------------------------------- #
# 6. Same finding twice wakes once (dedup = Z8 loop protection)
# --------------------------------------------------------------------------- #

_mt_repo_dedup="${_MT_WORK}/repo-dedup"
_mt_make_git_repo "$_mt_repo_dedup"
printf '<?php\nfunction bad() {}\n' > "${_mt_repo_dedup}/Bad.php"
_mt_phpstan_err_out='{"totals":{"file_errors":1,"other_errors":0},"files":{"x":{"errors":1,"messages":[{"message":"Param #1 expects int, string given.","line":2,"ignorable":true,"identifier":"argument.type"}]}},"errors":[]}'
_mt_stub_tool "${_mt_repo_dedup}/vendor/bin" "phpstan" "$_mt_phpstan_err_out"

_mt_sess_dedup="mt-dedup-$$"

# First run: new finding → exit 2.
_mt_exit_dedup1=0
jq -n \
    --arg sid "$_mt_sess_dedup" \
    --arg file "${_mt_repo_dedup}/Bad.php" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"<?php\n"}}' \
    | CLAUDE_PROJECT_DIR="$_mt_repo_dedup" \
      SLOPGUARD_MEDIUM_DEBOUNCE=0 \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=balanced \
      "${PLUGIN_ROOT}/bin/slopguard" post-write --tier=medium \
      2>/dev/null || _mt_exit_dedup1=$?
[ "$_mt_exit_dedup1" -eq 2 ] \
    && ok "medium: dedup: first run on error finding exits 2 (wakes agent)" \
    || bad "medium: dedup first run" "expected exit 2, got ${_mt_exit_dedup1}"

# Second run: same finding already fingerprinted → no new finding → exit 0.
_mt_exit_dedup2=0
jq -n \
    --arg sid "$_mt_sess_dedup" \
    --arg file "${_mt_repo_dedup}/Bad.php" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"<?php\n"}}' \
    | CLAUDE_PROJECT_DIR="$_mt_repo_dedup" \
      SLOPGUARD_MEDIUM_DEBOUNCE=0 \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=balanced \
      "${PLUGIN_ROOT}/bin/slopguard" post-write --tier=medium \
      2>/dev/null || _mt_exit_dedup2=$?
[ "$_mt_exit_dedup2" -eq 0 ] \
    && ok "medium: dedup: second run on same finding exits 0 (no rewake = Z8 protection)" \
    || bad "medium: dedup second run" "expected exit 0, got ${_mt_exit_dedup2}"

# --------------------------------------------------------------------------- #
# 7. Debounce coalesces two rapid edits into one run
# --------------------------------------------------------------------------- #

_mt_repo_db="${_MT_WORK}/repo-debounce"
_mt_make_git_repo "$_mt_repo_db"
printf '<?php\nfunction qux() {}\n' > "${_mt_repo_db}/Qux.php"
_mt_db_counter="${_MT_WORK}/.mt-db-counter"
printf '' > "$_mt_db_counter"  # empty counter
_mt_phpstan_empty='{"totals":{"file_errors":0},"files":{},"errors":[]}'
_mt_stub_counting_tool "${_mt_repo_db}/vendor/bin" "phpstan" \
    "$_mt_phpstan_empty" "$_mt_db_counter"

_mt_db_sess="mt-db-$$"
_mt_db_tmp1="$(mktemp "${_MT_WORK}/.mt-db1.XXXXXX")"
_mt_db_tmp2="$(mktemp "${_MT_WORK}/.mt-db2.XXXXXX")"

# Two concurrent invocations 0.3s apart; debounce=1s.
# The first invocation writes its token at T, sleeps 1s.
# The second writes its token at T+0.3s, sleeps 1s.
# At T+1s: first reads token = second's (not its own) → yields (no tool run).
# At T+1.3s: second reads its own token → proceeds → runs phpstan once.
export SLOPGUARD_MEDIUM_DEBOUNCE=1
export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE=project-first
(
    CLAUDE_PROJECT_DIR="$_mt_repo_db" \
    dispatch_medium "${_mt_repo_db}/Qux.php" "$_mt_db_sess" "" \
        "$_mt_repo_db" "$_mt_db_tmp1"
) 2>/dev/null &
_mt_db_pid1=$!

sleep 0.3

(
    CLAUDE_PROJECT_DIR="$_mt_repo_db" \
    dispatch_medium "${_mt_repo_db}/Qux.php" "$_mt_db_sess" "" \
        "$_mt_repo_db" "$_mt_db_tmp2"
) 2>/dev/null &
_mt_db_pid2=$!

wait $_mt_db_pid1 $_mt_db_pid2 2>/dev/null || true
unset SLOPGUARD_MEDIUM_DEBOUNCE

_mt_db_invocs=0
[ -f "$_mt_db_counter" ] && _mt_db_invocs="$(wc -c < "$_mt_db_counter" 2>/dev/null | tr -d ' ')"
[ "$_mt_db_invocs" -eq 1 ] \
    && ok "medium: debounce coalesces two rapid edits into one tool run" \
    || bad "medium: debounce coalesce" \
       "expected 1 invocation, got ${_mt_db_invocs} (may be timing-sensitive)"

# --------------------------------------------------------------------------- #
# 8. End-to-end wiring: slopguard post-write --tier=medium
# --------------------------------------------------------------------------- #
# Drive through bin/slopguard; verify that a phpstan error finding causes
# exit 2 and the §4.7 message is emitted on stderr.

_mt_e2e_repo="${_MT_WORK}/repo-e2e"
_mt_make_git_repo "$_mt_e2e_repo"
# Untracked PHP file (triggers --level=max in phpstan runner).
printf '<?php\nfunction send($msg) { eval($msg); }\n' > "${_mt_e2e_repo}/Eval.php"
_mt_e2e_phpstan='{"totals":{"file_errors":1,"other_errors":0},"files":{"x":{"errors":1,"messages":[{"message":"Parameter #1 expects int, string given.","line":2,"ignorable":true,"identifier":"argument.type"}]}},"errors":[]}'
_mt_stub_tool "${_mt_e2e_repo}/vendor/bin" "phpstan" "$_mt_e2e_phpstan"

_mt_e2e_sess="mt-e2e-$$"
_mt_e2e_stderr="$(mktemp "${_MT_WORK}/.mt-e2e-stderr.XXXXXX")"
_mt_e2e_exit=0
jq -n \
    --arg sid "$_mt_e2e_sess" \
    --arg file "${_mt_e2e_repo}/Eval.php" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"<?php\n"}}' \
    | CLAUDE_PROJECT_DIR="$_mt_e2e_repo" \
      SLOPGUARD_MEDIUM_DEBOUNCE=0 \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=balanced \
      "${PLUGIN_ROOT}/bin/slopguard" post-write --tier=medium \
      2>"$_mt_e2e_stderr" || _mt_e2e_exit=$?

[ "$_mt_e2e_exit" -eq 2 ] \
    && ok "medium: e2e: slopguard post-write --tier=medium exits 2 with error finding" \
    || bad "medium: e2e exit code" \
       "expected 2, got ${_mt_e2e_exit} (stderr: $(cat "$_mt_e2e_stderr" | head -3))"

grep -q 'slopguard:' "$_mt_e2e_stderr" \
    && ok "medium: e2e: §4.7 header present in stderr" \
    || bad "medium: e2e §4.7 header" "stderr: $(cat "$_mt_e2e_stderr" | head -5)"

grep -q 'medium tier' "$_mt_e2e_stderr" \
    && ok "medium: e2e: stderr identifies medium tier" \
    || bad "medium: e2e tier label" "stderr: $(cat "$_mt_e2e_stderr" | head -5)"

grep -q 'AP-PHP-MAINT-001' "$_mt_e2e_stderr" \
    && ok "medium: e2e: AP-id AP-PHP-MAINT-001 present" \
    || bad "medium: e2e AP-id" "stderr: $(cat "$_mt_e2e_stderr" | head -5)"
