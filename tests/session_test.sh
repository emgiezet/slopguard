#!/usr/bin/env bash
# tests/session_test.sh — tests for hooks/session-start and rules/policies/always-on.yaml.
#
# Standalone: cd plugins/slop-guard && bash tests/session_test.sh
# The ok()/bad() helpers are defined locally so this file runs independently.
# It intentionally does NOT source run-tests counters (run in isolation per
# the acceptance criteria: "run only this task's tests").

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

# Isolated data dir so we never collide with a real session.
_TEST_DATA="${TMPDIR:-/tmp}/slop-guard-session-test-$$"
export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
export CLAUDE_PLUGIN_DATA="${_TEST_DATA}"

PASS=0; FAIL=0
ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s: %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

HOOK="${PLUGIN_ROOT}/hooks/session-start"
POLICY="${PLUGIN_ROOT}/rules/policies/always-on.yaml"
WORK="${TMPDIR:-/tmp}/slop-guard-session-work-$$"
mkdir -p "${WORK}" "${_TEST_DATA}"

_cleanup() { rm -rf "${WORK}" "${_TEST_DATA}"; }
trap '_cleanup' EXIT INT TERM

# Minimal SessionStart JSON payload (all fields Claude Code provides).
SESSION_JSON='{"session_id":"test-sess-001","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'

printf 'session-start tests\n\n'

# --------------------------------------------------------------------------- #
# 1. Artefacts exist and are executable
# --------------------------------------------------------------------------- #

[ -f "${HOOK}" ] \
    && ok  "hook script exists: hooks/session-start" \
    || bad "hook script exists" "not found: ${HOOK}"

[ -x "${HOOK}" ] \
    && ok  "hook script is executable" \
    || bad "hook script is executable" "not executable: ${HOOK}"

[ -f "${POLICY}" ] \
    && ok  "policy file exists: rules/policies/always-on.yaml" \
    || bad "policy file exists" "not found: ${POLICY}"

# --------------------------------------------------------------------------- #
# 2. always-on.yaml — content checks
# --------------------------------------------------------------------------- #

for _id in AP-AGENT-001 AP-AGENT-002 AP-AGENT-003 AP-AGENT-004 \
           AP-AGENT-005 AP-AGENT-006 AP-AGENT-007; do
    grep -q "${_id}" "${POLICY}" \
        && ok  "always-on.yaml: contains ${_id}" \
        || bad "always-on.yaml: contains ${_id}" "missing from ${POLICY}"
done

grep -q 'skill_reference' "${POLICY}" \
    && ok  "always-on.yaml: has skill_reference field" \
    || bad "always-on.yaml: has skill_reference field" "missing skill_reference"

grep -q 'digest_max_lines' "${POLICY}" \
    && ok  "always-on.yaml: has digest_max_lines field" \
    || bad "always-on.yaml: has digest_max_lines field" "missing digest_max_lines"

# --------------------------------------------------------------------------- #
# 3. session-start output: empty project
# --------------------------------------------------------------------------- #

_empty="${WORK}/empty"
mkdir -p "${_empty}"

_out="$(printf '%s\n' "${SESSION_JSON}" \
    | CLAUDE_PROJECT_DIR="${_empty}" "${HOOK}" 2>/dev/null)"

printf '%s\n' "${_out}" | grep -qE 'stacks \(auto\):' \
    && ok  "empty project: outputs source-labelled stacks line" \
    || bad "empty project: outputs source-labelled stacks line" "missing in: ${_out}"

printf '%s\n' "${_out}" | grep -q 'missing tools:.*doctor --install' \
    && ok  "missing tools: first session start reports install command" \
    || bad "missing tools: first session start reports install command" "${_out}"

_out_repeat="$(printf '%s\n' "${SESSION_JSON}" \
    | CLAUDE_PROJECT_DIR="${_empty}" "${HOOK}" 2>/dev/null)"
if printf '%s\n' "${_out_repeat}" | grep -q 'missing tools:'; then
    bad "missing tools: report appears once per session" "${_out_repeat}"
else
    ok "missing tools: report appears once per session"
fi

# --------------------------------------------------------------------------- #
# 4. Stack detection: Go project
# --------------------------------------------------------------------------- #

_go="${WORK}/go-proj"
mkdir -p "${_go}"
printf 'module example.com/demo\n\ngo 1.23\n' > "${_go}/go.mod"

_out_go="$(printf '%s\n' "${SESSION_JSON}" \
    | CLAUDE_PROJECT_DIR="${_go}" "${HOOK}" 2>/dev/null)"

printf '%s\n' "${_out_go}" | grep -q 'go' \
    && ok  "stack detection: go.mod → detects go" \
    || bad "stack detection: go.mod → detects go" "${_out_go}"

# --------------------------------------------------------------------------- #
# 5. Stack detection: Laravel project (composer.json + artisan)
# --------------------------------------------------------------------------- #

_laravel="${WORK}/laravel-proj"
mkdir -p "${_laravel}"
printf '{"require":{"laravel/framework":"^11.0"}}' > "${_laravel}/composer.json"
touch "${_laravel}/artisan"

_out_laravel="$(printf '%s\n' "${SESSION_JSON}" \
    | CLAUDE_PROJECT_DIR="${_laravel}" "${HOOK}" 2>/dev/null)"

printf '%s\n' "${_out_laravel}" | grep -q 'php' \
    && ok  "stack detection: composer.json → detects php" \
    || bad "stack detection: composer.json → detects php" "${_out_laravel}"

printf '%s\n' "${_out_laravel}" | grep -q 'laravel' \
    && ok  "stack detection: artisan + laravel/framework → detects laravel" \
    || bad "stack detection: artisan + laravel/framework → detects laravel" "${_out_laravel}"

# --------------------------------------------------------------------------- #
# 6. Session state: profile.json written with stacks
# --------------------------------------------------------------------------- #

_sess_dir="${_TEST_DATA}/sessions/test-sess-001"
[ -f "${_sess_dir}/profile.json" ] \
    && ok  "session state: profile.json created" \
    || bad "session state: profile.json created" "missing: ${_sess_dir}/profile.json"

if [ -f "${_sess_dir}/profile.json" ]; then
    _stacks_val="$(jq -r '.stacks | type' "${_sess_dir}/profile.json" 2>/dev/null || printf 'ERROR')"
    [ "${_stacks_val}" = "array" ] \
        && ok  "session state: profile.json .stacks is an array" \
        || bad "session state: profile.json .stacks is an array" "got type: ${_stacks_val}"

    _src_val="$(jq -r '.stacks_source' "${_sess_dir}/profile.json" 2>/dev/null || printf 'ERROR')"
    [ -n "${_src_val}" ] && [ "${_src_val}" != "null" ] \
        && ok  "session state: profile.json .stacks_source present" \
        || bad "session state: profile.json .stacks_source present" "got: ${_src_val}"

    _warn_type="$(jq -r '.stacks_warnings | type' "${_sess_dir}/profile.json" 2>/dev/null || printf 'ERROR')"
    [ "${_warn_type}" = "array" ] \
        && ok  "session state: profile.json .stacks_warnings is an array" \
        || bad "session state: profile.json .stacks_warnings is an array" "got type: ${_warn_type}"
fi
    _tool_shape="$(jq -r '.tools[0] | has("name") and has("source") and has("version") and has("config_path") and has("config_source")' "${_sess_dir}/profile.json")"
    [ "${_tool_shape}" = "true" ] \
        && ok  "session state: tool records include source/version/config" \
        || bad "session state: tool records" "required fields missing"

    _ruff_config_source="$(jq -r '.tools[] | select(.name == "ruff") | .config_source' "${_sess_dir}/profile.json")"
    _ruff_config_path="$(jq -r '.tools[] | select(.name == "ruff") | .config_path' "${_sess_dir}/profile.json")"
    if [ "${_ruff_config_source}" = "baseline" ] \
        && [ "${_ruff_config_path}" = "${PLUGIN_ROOT}/configs/baseline/ruff.toml" ]; then
        ok "session state: tool records contain resolved baseline configs"
    else
        bad "session state: resolved tool config" \
            "source=${_ruff_config_source} path=${_ruff_config_path}"
    fi

# --------------------------------------------------------------------------- #
# 7. Stack detection: negative config case (project vs baseline)
# --------------------------------------------------------------------------- #

_php_proj="${WORK}/php-proj-config"
mkdir -p "${_php_proj}"
printf '{"require":{}}' > "${_php_proj}/composer.json"
touch "${_php_proj}/phpstan.dist.neon" # project config
_out_php_proj="$(printf '%s\n' "${SESSION_JSON}" \
    | CLAUDE_PROJECT_DIR="${_php_proj}" "${HOOK}" 2>/dev/null)"

_php_cfg="$(jq -r '.config_sources.php' "${_sess_dir}/profile.json")"
[ "${_php_cfg}" = "project" ] \
    && ok  "config resolution: phpstan.dist.neon present → php source: project" \
    || bad "config resolution: phpstan.dist.neon present → php source: project" "got: ${_php_cfg}"

_php_base="${WORK}/php-proj-baseline"
mkdir -p "${_php_base}"
printf '{"require":{}}' > "${_php_base}/composer.json"

_out_php_base="$(printf '%s\n' "${SESSION_JSON}" \
    | CLAUDE_PROJECT_DIR="${_php_base}" "${HOOK}" 2>/dev/null)"

_php_cfg_base="$(jq -r '.config_sources.php' "${_sess_dir}/profile.json")"
[ "${_php_cfg_base}" = "baseline" ] \
    && ok  "config resolution: no config → php source: baseline" \
    || bad "config resolution: no config → php source: baseline" "got: ${_php_cfg_base}"


_python_proj="${WORK}/python-project-config"
mkdir -p "${_python_proj}"
printf '[tool.pyright]\n' > "${_python_proj}/pyproject.toml"
printf '%s\n' "${SESSION_JSON}" | CLAUDE_PROJECT_DIR="${_python_proj}" "${HOOK}" >/dev/null 2>&1
_python_cfg="$(jq -r '.config_sources.python' "${_sess_dir}/profile.json")"
[ "${_python_cfg}" = "project" ] \
    && ok  "config resolution: pyproject [tool.pyright] → python source: project" \
    || bad "config resolution: pyright project config" "got: ${_python_cfg}"

_node_proj="${WORK}/node-project-config"
mkdir -p "${_node_proj}"
printf '{}\n' > "${_node_proj}/package.json"
printf '{}\n' > "${_node_proj}/.eslintrc.json"
printf '%s\n' "${SESSION_JSON}" | CLAUDE_PROJECT_DIR="${_node_proj}" "${HOOK}" >/dev/null 2>&1
_node_cfg="$(jq -r '.config_sources.node' "${_sess_dir}/profile.json")"
[ "${_node_cfg}" = "project" ] \
    && ok  "config resolution: .eslintrc.json → node source: project" \
    || bad "config resolution: eslint project config" "got: ${_node_cfg}"
# --------------------------------------------------------------------------- #
# 8. Public dispatcher forwards stdin to the session hook
# --------------------------------------------------------------------------- #

_dispatch_json='{"session_id":"dispatch-sess","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
printf '%s\n' "${_dispatch_json}" \
    | CLAUDE_PROJECT_DIR="${_go}" "${PLUGIN_ROOT}/bin/slopguard" session-start >/dev/null 2>&1
[ -f "${_TEST_DATA}/sessions/dispatch-sess/profile.json" ] \
    && ok  "dispatcher: session-start preserves hook input" \
    || bad "dispatcher: session-start preserves hook input" "profile.json not created"

_old_dir="${_TEST_DATA}/sessions/resume-old"
mkdir -p "$_old_dir"
touch -t 202001010000 "$_old_dir"
_resume_json='{"session_id":"resume-old","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
printf '%s\n' "${_resume_json}" | CLAUDE_PROJECT_DIR="${_go}" "${HOOK}" >/dev/null 2>&1
[ -f "${_old_dir}/profile.json" ] \
    && ok  "session prune: resumed stale session is re-created" \
    || bad "session prune: resumed stale session" "profile.json missing after resume"

# --------------------------------------------------------------------------- #
# 9. plugin-validate passes

if command -v claude >/dev/null 2>&1; then
    _val_out="$(claude plugin validate "${PLUGIN_ROOT}" --strict 2>&1)"
    _val_exit=$?
    [ "${_val_exit}" -eq 0 ] \
        && ok  "claude plugin validate --strict: passes" \
        || bad "claude plugin validate --strict: passes" "${_val_out}"
else
    printf '  skip  claude plugin validate: claude CLI not available\n'
fi

# --------------------------------------------------------------------------- #
# 10. framework_versions in profile.json + AP-AGENT-008/009 in digest
# --------------------------------------------------------------------------- #

# Temp stacks.json with context7 added to laravel (Context7Data applies this
# to the real stacks.json; here we inject it for isolated testing).
_tmp_stacks="${WORK}/test-stacks.json"
jq '.laravel += {"context7": "laravel"}' "${PLUGIN_ROOT}/rules/stacks.json" > "${_tmp_stacks}"

# Fixture: Laravel project WITH composer.lock containing laravel/framework.
_lv_lock="${WORK}/laravel-with-lock"
mkdir -p "${_lv_lock}"
printf '{"require":{"laravel/framework":"^12.0"}}' > "${_lv_lock}/composer.json"
touch "${_lv_lock}/artisan"
cat > "${_lv_lock}/composer.lock" <<'LOCKEOF'
{
    "packages": [
        {"name": "laravel/framework", "version": "v12.4.1"}
    ]
}
LOCKEOF

_fw_json='{"session_id":"fw-digest-001","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
_fw_out="$(printf '%s\n' "${_fw_json}" \
    | CLAUDE_PROJECT_DIR="${_lv_lock}" SLOPGUARD_STACKS_JSON="${_tmp_stacks}" "${HOOK}" 2>/dev/null)"
_fw_dir="${_TEST_DATA}/sessions/fw-digest-001"

if [ -f "${_fw_dir}/profile.json" ]; then
    _lv_ver="$(jq -r '.framework_versions.laravel // empty' "${_fw_dir}/profile.json")"
    [ -n "$_lv_ver" ] \
        && ok  "framework_versions: composer.lock yields .laravel (${_lv_ver})" \
        || bad "framework_versions: laravel version" "expected non-empty, got empty"
else
    bad "framework_versions: profile.json missing for fw-digest-001" ""
fi

# Fixture: Laravel project WITHOUT composer.lock → no laravel key.
_lv_nolock="${WORK}/laravel-nolock"
mkdir -p "${_lv_nolock}"
printf '{"require":{"laravel/framework":"^12.0"}}' > "${_lv_nolock}/composer.json"
touch "${_lv_nolock}/artisan"

_fw_nl_json='{"session_id":"fw-nolock-001","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
printf '%s\n' "${_fw_nl_json}" \
    | CLAUDE_PROJECT_DIR="${_lv_nolock}" SLOPGUARD_STACKS_JSON="${_tmp_stacks}" "${HOOK}" >/dev/null 2>&1
_fw_nl_dir="${_TEST_DATA}/sessions/fw-nolock-001"

if [ -f "${_fw_nl_dir}/profile.json" ]; then
    _nokey="$(jq -r '(.framework_versions // {}) | has("laravel") | not' "${_fw_nl_dir}/profile.json")"
    [ "$_nokey" = "true" ] \
        && ok  "framework_versions: missing composer.lock omits laravel key" \
        || bad "framework_versions: missing composer.lock" "laravel key unexpectedly present"
fi

# Digest must contain AP-AGENT-008 and AP-AGENT-009.
printf '%s\n' "${_fw_out}" | grep -q 'AP-AGENT-008' \
    && ok  "digest: AP-AGENT-008 present" \
    || bad "digest: AP-AGENT-008 present" "missing in digest"
printf '%s\n' "${_fw_out}" | grep -q 'AP-AGENT-009' \
    && ok  "digest: AP-AGENT-009 present" \
    || bad "digest: AP-AGENT-009 present" "missing in digest"

# --------------------------------------------------------------------------- #

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
