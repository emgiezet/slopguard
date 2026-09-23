#!/usr/bin/env bash
# config_mode_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.
#
# Covers the §2 Z1 config-source overlay (config_source knob):
#  1. tool_config_mode returns "project" when a project config exists.
#  2. No project config + default knob (overlay): maintainability finding dropped,
#     security finding reported.
#  3. No project config + config_source=full: both findings reported.
#  4. No project config + config_source=project-only: tool does not run at all.
#  5. Unmapped rule id in overlay mode: dropped (not promoted to security).
#  6. Unrecognised knob value: falls back to overlay.
#  7. Psalm taint findings survive overlay mode in lib/stop.sh (category=security).
#  8. Real-path e2e: bin/slopguard post-write --tier=fast, overlay mode,
#     security finding reported, style finding not reported.

# --------------------------------------------------------------------------- #
# Setup
# --------------------------------------------------------------------------- #

_CM_WORK="${TMPDIR:-/tmp}/slop-guard-cm-$$"
mkdir -p "${_CM_WORK}/vendor/bin"

_CM_OWN_DATA=false
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
    CLAUDE_PLUGIN_DATA="${_CM_WORK}/data"
    export CLAUDE_PLUGIN_DATA
    _CM_OWN_DATA=true
fi
mkdir -p "${CLAUDE_PLUGIN_DATA}/sessions"

_CM_OLD_TOOL_SOURCE="${CLAUDE_PLUGIN_OPTION_TOOL_SOURCE:-project-first}"
export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE=project-first

_cm_cleanup() {
    "$_CM_OWN_DATA" && unset CLAUDE_PLUGIN_DATA || true
    export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="$_CM_OLD_TOOL_SOURCE"
    rm -rf "$_CM_WORK"
}
trap '_cm_cleanup' EXIT INT TERM

# Source the libraries (same pattern as dispatch_test.sh).
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

# _cm_make_git_repo <dir>
_cm_make_git_repo() {
    local d="$1"
    mkdir -p "$d"
    git -C "$d" init -q 2>/dev/null
    git -C "$d" config user.email "test@cm.test" 2>/dev/null
    git -C "$d" config user.name  "CM Test"      2>/dev/null
}

# _cm_commit <repo> <file> <content>
_cm_commit() {
    printf '%s\n' "$3" > "${1}/${2}"
    git -C "$1" add "${2}" 2>/dev/null
    git -C "$1" commit -q -m "init" 2>/dev/null
}

# _cm_stub_ruff <bin_dir> <output>
_cm_stub_ruff() {
    local dir="$1" out="$2"
    mkdir -p "$dir"
    printf '#!/bin/sh\nprintf '"'"'%s'"'"'\n' \
        "$(printf '%s' "$out" | sed "s/'/'\\\\''/g")" > "${dir}/ruff"
    chmod +x "${dir}/ruff"
}

# _cm_count_findings <findings_tmp>
_cm_count_findings() {
    local n=0
    [ -s "$1" ] && n="$(grep -c '' "$1" 2>/dev/null || printf '0')"
    printf '%d' "$n"
}

# _cm_run_fast <project_dir> <file> <session_id>
# Runs dispatch_fast and returns the path to findings NDJSON file.
_cm_run_fast() {
    local project_dir="$1" file="$2" session_id="$3"
    local out; out="$(mktemp "${_CM_WORK}/.cm-findings.XXXXXX")"
    CLAUDE_PROJECT_DIR="$project_dir" \
        dispatch_fast "$file" "$session_id" "--" "$project_dir" "$out" 2>/dev/null || true
    printf '%s' "$out"
}

# _cm_count_by_ap <findings_tmp> <ap_id>
# Count findings matching an AP id.
_cm_count_by_ap() {
    local n=0
    [ -s "$1" ] && \
        n="$(grep -c "\"ap_id\":\"${2}\"" "$1" 2>/dev/null || printf '0')"
    printf '%d' "$n"
}

# --------------------------------------------------------------------------- #
# 1. tool_config_mode — project config present → "project"
# --------------------------------------------------------------------------- #

_cm1_repo="${_CM_WORK}/repo-has-config"
_cm_make_git_repo "$_cm1_repo"
_cm_commit "$_cm1_repo" "app.py" "x = 1"
# Create a project ruff.toml
printf '[lint]\nselect = ["ALL"]\n' > "${_cm1_repo}/ruff.toml"

_cm1_mode="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=overlay \
    tool_config_mode ruff "$_cm1_repo")"
[ "$_cm1_mode" = "project" ] \
    && ok  "config_mode: project config present → mode=project" \
    || bad "config_mode: project config present → mode=project" "got: ${_cm1_mode}"

# With project config, a maintainability finding on a changed line IS reported.
_cm_commit "$_cm1_repo" "query.py" "y = 1"
printf 'y = 2\n' > "${_cm1_repo}/query.py"

_cm1_ruff_out='[{"code":"T201","message":"print found","filename":"query.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":10},"fix":null,"noqa_row":null}]'
_cm_stub_ruff "${_cm1_repo}/vendor/bin" "$_cm1_ruff_out"
_cm1_tmp="$(_cm_run_fast "$_cm1_repo" "${_cm1_repo}/query.py" "cm1-$$")"
_cm1_n="$(_cm_count_findings "$_cm1_tmp")"
[ "$_cm1_n" -eq 1 ] \
    && ok  "config_mode: project config → maintainability finding reported (project mode)" \
    || bad "config_mode: project config → maintainability reported" "expected 1, got ${_cm1_n}"

# --------------------------------------------------------------------------- #
# 2. Default knob (overlay): security reported, maintainability dropped
# --------------------------------------------------------------------------- #

_cm2_repo="${_CM_WORK}/repo-no-config"
_cm_make_git_repo "$_cm2_repo"
_cm_commit "$_cm2_repo" "app.py" "x = 1"
printf 'query = "SELECT * WHERE id = %%s" %% uid\n' > "${_cm2_repo}/app.py"

# Verify mode = overlay
_cm2_mode="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=overlay \
    tool_config_mode ruff "$_cm2_repo")"
[ "$_cm2_mode" = "overlay" ] \
    && ok  "config_mode: no project config, default knob → mode=overlay" \
    || bad "config_mode: no project config, default knob → mode=overlay" "got: ${_cm2_mode}"

# Two findings: S608 (security) at line 1, T201 (maintainability) at line 1.
# Both are on the changed line, so Z2 would not filter either.
# Overlay mode must keep S608 and drop T201.
_cm2_ruff_two='[{"code":"S608","message":"SQL injection","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":40},"fix":null,"noqa_row":null},{"code":"T201","message":"print found","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":10},"fix":null,"noqa_row":null}]'
_cm_stub_ruff "${_cm2_repo}/vendor/bin" "$_cm2_ruff_two"
_cm2_tmp="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=overlay \
    _cm_run_fast "$_cm2_repo" "${_cm2_repo}/app.py" "cm2-$$")"
_cm2_total="$(_cm_count_findings "$_cm2_tmp")"
_cm2_sec="$(_cm_count_by_ap "$_cm2_tmp" "AP-PY-SEC-001")"

[ "$_cm2_sec" -eq 1 ] \
    && ok  "config_mode: overlay — security finding (S608→AP-PY-SEC-001) IS reported" \
    || bad "config_mode: overlay — security finding reported" "expected 1, got ${_cm2_sec}"

[ "$_cm2_total" -eq 1 ] \
    && ok  "config_mode: overlay — maintainability finding (T201) is NOT reported" \
    || bad "config_mode: overlay — maintainability dropped" "expected 1 total, got ${_cm2_total}"

# --------------------------------------------------------------------------- #
# 3. config_source=full: both findings reported
# --------------------------------------------------------------------------- #

_cm3_ruff_two="$_cm2_ruff_two"
_cm_stub_ruff "${_cm2_repo}/vendor/bin" "$_cm3_ruff_two"
_cm3_tmp="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=full \
    _cm_run_fast "$_cm2_repo" "${_cm2_repo}/app.py" "cm3-$$")"
_cm3_total="$(_cm_count_findings "$_cm3_tmp")"

[ "$_cm3_total" -eq 2 ] \
    && ok  "config_mode: full — both findings (security + maintainability) reported" \
    || bad "config_mode: full — both reported" "expected 2, got ${_cm3_total}"

# --------------------------------------------------------------------------- #
# 4. config_source=project-only: tool does not run
# --------------------------------------------------------------------------- #

_cm4_repo="${_CM_WORK}/repo-project-only"
_cm_make_git_repo "$_cm4_repo"
_cm_commit "$_cm4_repo" "app.py" "x = 1"
printf 'y = 2\n' > "${_cm4_repo}/app.py"

_cm4_marker="${_CM_WORK}/.cm4-marker"
rm -f "$_cm4_marker"

# Ruff stub writes to the marker when invoked.
mkdir -p "${_cm4_repo}/vendor/bin"
cat > "${_cm4_repo}/vendor/bin/ruff" << STUBEOF
#!/bin/sh
touch "${_cm4_marker}"
printf '[{"code":"S608","message":"SQL injection","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":40},"fix":null,"noqa_row":null}]'
STUBEOF
chmod +x "${_cm4_repo}/vendor/bin/ruff"

_cm4_tmp="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=project-only \
    _cm_run_fast "$_cm4_repo" "${_cm4_repo}/app.py" "cm4-$$")"
_cm4_n="$(_cm_count_findings "$_cm4_tmp")"

[ "$_cm4_n" -eq 0 ] \
    && ok  "config_mode: project-only — no findings produced (tool skipped)" \
    || bad "config_mode: project-only — no findings" "expected 0, got ${_cm4_n}"

[ ! -f "$_cm4_marker" ] \
    && ok  "config_mode: project-only — ruff stub never invoked (marker absent)" \
    || bad "config_mode: project-only — tool not invoked" "marker file was created"

# --------------------------------------------------------------------------- #
# 5. Unmapped rule id in overlay mode: dropped (not promoted to security)
# --------------------------------------------------------------------------- #

_cm5_repo="${_CM_WORK}/repo-unmapped"
_cm_make_git_repo "$_cm5_repo"
_cm_commit "$_cm5_repo" "app.py" "x = 1"
printf 'y = 2\n' > "${_cm5_repo}/app.py"

# ZZZZ999 is not in ruff.yaml → unmapped → default category=maintainability → dropped in overlay.
_cm5_ruff='[{"code":"ZZZZ999","message":"some unmapped warning","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":20},"fix":null,"noqa_row":null}]'
_cm_stub_ruff "${_cm5_repo}/vendor/bin" "$_cm5_ruff"
_cm5_tmp="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=overlay \
    _cm_run_fast "$_cm5_repo" "${_cm5_repo}/app.py" "cm5-$$")"
_cm5_n="$(_cm_count_findings "$_cm5_tmp")"

[ "$_cm5_n" -eq 0 ] \
    && ok  "config_mode: overlay — unmapped rule id is dropped (not promoted to security)" \
    || bad "config_mode: overlay — unmapped dropped" "expected 0, got ${_cm5_n}"

# --------------------------------------------------------------------------- #
# 6. Unrecognised knob value falls back to overlay
# --------------------------------------------------------------------------- #

_cm6_mode="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=typo_value \
    tool_config_mode ruff "${_cm2_repo}")"
[ "$_cm6_mode" = "overlay" ] \
    && ok  "config_mode: unrecognised knob ('typo_value') → fallback to overlay" \
    || bad "config_mode: unrecognised knob fallback" "got: ${_cm6_mode}"

# Verify that the fallback actually silences a maintainability finding.
_cm_stub_ruff "${_cm2_repo}/vendor/bin" "$_cm2_ruff_two"
_cm6_tmp="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=typo_value \
    _cm_run_fast "$_cm2_repo" "${_cm2_repo}/app.py" "cm6-$$")"
_cm6_total="$(_cm_count_findings "$_cm6_tmp")"
_cm6_sec="$(_cm_count_by_ap "$_cm6_tmp" "AP-PY-SEC-001")"

[ "$_cm6_sec" -eq 1 ] && [ "$_cm6_total" -eq 1 ] \
    && ok  "config_mode: unrecognised knob → overlay behaviour (security kept, maint dropped)" \
    || bad "config_mode: unrecognised knob overlay behaviour" \
           "sec=${_cm6_sec} total=${_cm6_total} (expected sec=1 total=1)"

# --------------------------------------------------------------------------- #
# 7. Psalm taint findings survive overlay mode in lib/stop.sh
# --------------------------------------------------------------------------- #
# Source stop.sh (its deps are already loaded above).
# shellcheck source=../lib/stop.sh
. "${PLUGIN_ROOT}/lib/stop.sh"

_cm7_repo="${_CM_WORK}/repo-psalm"
mkdir -p "${_cm7_repo}/vendor/bin"
_cm_make_git_repo "$_cm7_repo"
_cm_commit "$_cm7_repo" "seed.php" "<?php"
# Uncommitted PHP change.
printf '<?php $pdo->query("SELECT * WHERE id=" . $_GET["id"]);\n' \
    > "${_cm7_repo}/Controller.php"

# Psalm stub emits TaintedSql (category=security).
cat > "${_cm7_repo}/vendor/bin/psalm" << 'STUBEOF'
#!/bin/sh
printf '[{"type":"TaintedSql","file_path":"Controller.php","file_name":"Controller.php","line_from":1,"line_to":1,"message":"Tainted SQL from $_GET","snippet":"$pdo->query(...)","severity":"error","shortcode":200}]\n'
STUBEOF
chmod +x "${_cm7_repo}/vendor/bin/psalm"

_cm7_sess="cm7-psalm-$$"
_cm7_sdir="${CLAUDE_PLUGIN_DATA}/sessions/${_cm7_sess}"
mkdir -p "$_cm7_sdir"
printf '[]\n' > "${_cm7_sdir}/findings.json"
printf '0\n'  > "${_cm7_sdir}/stop-iterations"

_cm7_changed="$(cd "$_cm7_repo" && git diff HEAD --name-only 2>/dev/null || true)
$(cd "$_cm7_repo" && git ls-files --others --exclude-standard 2>/dev/null || true)"

# Run psalm runner in overlay mode (no project psalm.xml → mode=overlay).
# All psalm taint findings are category=security, so overlay must NOT silence them.
CLAUDE_PROJECT_DIR="$_cm7_repo" \
    CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=overlay \
    PATH="${_cm7_repo}/vendor/bin:${PATH}" \
_stop_run_psalm "$_cm7_sess" "--" "$_cm7_repo" "$_cm7_changed" 2>/dev/null || true

_cm7_count="$(jq 'length' "${_cm7_sdir}/findings.json" 2>/dev/null || printf '0')"
[ "$_cm7_count" -ge 1 ] \
    && ok  "config_mode: psalm TaintedSql survives overlay mode (category=security)" \
    || bad "config_mode: psalm overlay not silencing taint" "expected ≥1 findings, got ${_cm7_count}"

_cm7_cat="$(jq -r '.[0].category // empty' "${_cm7_sdir}/findings.json" 2>/dev/null || true)"
[ "$_cm7_cat" = "security" ] \
    && ok  "config_mode: psalm overlay: finding category is security" \
    || bad "config_mode: psalm overlay category" "got: ${_cm7_cat}"

# --------------------------------------------------------------------------- #
# 8. Real-path e2e: bin/slopguard post-write --tier=fast, overlay mode
#    Security finding reported; style finding not reported.
# --------------------------------------------------------------------------- #

_cm8_repo="${_CM_WORK}/repo-e2e"
_cm_make_git_repo "$_cm8_repo"
_cm_commit "$_cm8_repo" "app.py" "x = 1"
# Changed line 1 (untracked would also work, but let's use a tracked diff).
printf 'query = "SELECT * FROM t WHERE id = %%s" %% uid\n' > "${_cm8_repo}/app.py"

# Ruff stub: two findings on line 1 — S608 (security) and T201 (maintainability).
_cm8_ruff='[{"code":"S608","message":"Possible SQL injection","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":50},"fix":null,"noqa_row":null},{"code":"T201","message":"print found","filename":"app.py","url":"","location":{"row":1,"column":1},"end_location":{"row":1,"column":10},"fix":null,"noqa_row":null}]'
_cm_stub_ruff "${_cm8_repo}/vendor/bin" "$_cm8_ruff"

_cm8_sess="cm8-e2e-$$"
_cm8_out=""
_cm8_out="$(jq -n \
    --arg sid "$_cm8_sess" \
    --arg file "${_cm8_repo}/app.py" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"query = ..."}}' \
    | CLAUDE_PROJECT_DIR="$_cm8_repo" \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=advisory \
      CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=overlay \
      "${PLUGIN_ROOT}/hooks/post-write" 2>/dev/null || true)"

_cm8_ctx="$(printf '%s\n' "$_cm8_out" \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"

printf '%s\n' "$_cm8_ctx" | grep -q 'AP-PY-SEC-001' \
    && ok  "config_mode: e2e overlay — security finding AP-PY-SEC-001 (S608) is reported" \
    || bad "config_mode: e2e overlay — security finding present" "ctx=${_cm8_ctx}"

printf '%s\n' "$_cm8_ctx" | grep -q 'T201' \
    && bad "config_mode: e2e overlay — style finding T201 should NOT appear" "ctx=${_cm8_ctx}" \
    || ok  "config_mode: e2e overlay — style finding (T201/maintainability) is NOT reported"

# Full mode: both findings reported.
_cm8_full_sess="cm8-full-$$"
_cm8_full_out=""
_cm_stub_ruff "${_cm8_repo}/vendor/bin" "$_cm8_ruff"
_cm8_full_out="$(jq -n \
    --arg sid "$_cm8_full_sess" \
    --arg file "${_cm8_repo}/app.py" \
    '{session_id:$sid,agent_id:null,tool_name:"Write",
      tool_input:{file_path:$file,content:"query = ..."}}' \
    | CLAUDE_PROJECT_DIR="$_cm8_repo" \
      CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=advisory \
      CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=full \
      "${PLUGIN_ROOT}/hooks/post-write" 2>/dev/null || true)"

_cm8_full_ctx="$(printf '%s\n' "$_cm8_full_out" \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"

printf '%s\n' "$_cm8_full_ctx" | grep -q 'T201' \
    && ok  "config_mode: e2e full — style finding T201 IS reported in full mode" \
    || bad "config_mode: e2e full — style finding present" "ctx=${_cm8_full_ctx}"

printf '%s\n' "$_cm8_full_ctx" | grep -q 'AP-PY-SEC-001' \
    && ok  "config_mode: e2e full — security finding AP-PY-SEC-001 also present" \
    || bad "config_mode: e2e full — security finding present" "ctx=${_cm8_full_ctx}"
