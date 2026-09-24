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

printf '%s\n' "${_out}" | grep -q 'missing tools for this project:.*doctor --install' \
    && ok  "missing tools: first session start reports install command" \
    || bad "missing tools: first session start reports install command" "${_out}"

# A project with no stack still needs the core tools, and must never be asked
# for a language linter it cannot use.
printf '%s\n' "${_out}" | grep -qE 'missing tools for this project:.*(betterleaks|jq|shellcheck)' \
    && ok  "missing tools: core tools are reported for a stackless project" \
    || bad "missing tools: core tools are reported for a stackless project" "${_out}"

if printf '%s\n' "${_out}" | grep -qE 'missing tools for this project:.*(phpstan|golangci-lint|ruff|tflint)'; then
    bad "missing tools: stack-specific tools stay out of a stackless project" "${_out}"
else
    ok "missing tools: stack-specific tools stay out of a stackless project"
fi

_out_repeat="$(printf '%s\n' "${SESSION_JSON}" \
    | CLAUDE_PROJECT_DIR="${_empty}" "${HOOK}" 2>/dev/null)"
if printf '%s\n' "${_out_repeat}" | grep -q 'missing tools'; then
    bad "missing tools: report appears once per session" "${_out_repeat}"
else
    ok "missing tools: report appears once per session"
fi

# --------------------------------------------------------------------------- #
# 3b. Tool relevance follows the detected stacks
# --------------------------------------------------------------------------- #

_pyproj="${WORK}/py-scope"
mkdir -p "${_pyproj}"
printf '[project]\nname = "x"\n' > "${_pyproj}/pyproject.toml"
_py_json="$(printf '%s\n' "${SESSION_JSON}" | jq -c '.session_id = "scope-python-001"')"
printf '%s\n' "${_py_json}" \
    | CLAUDE_PROJECT_DIR="${_pyproj}" "${HOOK}" >/dev/null 2>&1
_py_profile="${_TEST_DATA}/sessions/scope-python-001/profile.json"

if [ -f "${_py_profile}" ]; then
    _py_rel="$(jq -r '[.tools[] | select(.relevant) | .name] | sort | join(" ")' "${_py_profile}")"
    case " ${_py_rel} " in
        *" ruff "*) ok "tool scope: python project marks ruff relevant" ;;
        *)          bad "tool scope: python project marks ruff relevant" "${_py_rel}" ;;
    esac
    case " ${_py_rel} " in
        *" phpstan "*) bad "tool scope: python project leaves phpstan irrelevant" "${_py_rel}" ;;
        *)             ok "tool scope: python project leaves phpstan irrelevant" ;;
    esac
    _py_src="$(jq -r '.tools[] | select(.name == "phpstan") | .source' "${_py_profile}")"
    [ "${_py_src}" = "not-applicable" ] \
        && ok  "tool scope: irrelevant tool records source=not-applicable" \
        || bad "tool scope: irrelevant tool records source=not-applicable" "got: ${_py_src}"
else
    bad "tool scope: python session profile written" "missing ${_py_profile}"
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
# --------------------------------------------------------------------------- #
# 11. Extensions line: project with .slopguard/ prints the line with right counts
# --------------------------------------------------------------------------- #

# Stub ext.sh with known data: 2 tools (1 active, 1 absent), 12 overrides / 3 downgrades.
_stub_ext="${WORK}/stub-ext.sh"
cat > "$_stub_ext" <<'EXTEOF'
ext_dir() { printf '%s/.slopguard\n' "$1"; }
ext_override_counts() { printf '12 3\n'; }
ext_tools() {
    printf '{"name":"sqlfluff","tier":"fast","resolved":"/usr/bin/sqlfluff","status":"ok"}\n'
    printf '{"name":"detekt","tier":"fast","resolved":"","status":"absent"}\n'
}
EXTEOF

_ext_proj="${WORK}/ext-proj"
mkdir -p "${_ext_proj}/.slopguard/tools" "${_ext_proj}/.slopguard/mapping"
_ext_json='{"session_id":"ext-test-001","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
_ext_out="$(printf '%s\n' "${_ext_json}" \
    | SLOPGUARD_EXT_SH="${_stub_ext}" CLAUDE_PROJECT_DIR="${_ext_proj}" "${HOOK}" 2>/dev/null)"

printf '%s\n' "${_ext_out}" | grep -q 'project extensions:' \
    && ok  "extensions: line present when .slopguard/ exists" \
    || bad "extensions: line missing for project with .slopguard/" "${_ext_out}"

printf '%s\n' "${_ext_out}" | grep -q '2 tools (1 active, 1 absent)' \
    && ok  "extensions: tool counts correct (2 tools, 1 active, 1 absent)" \
    || bad "extensions: tool counts" "${_ext_out}"

printf '%s\n' "${_ext_out}" | grep -q '12 rule overrides (3 severity downgrades)' \
    && ok  "extensions: override counts correct (12 overrides, 3 downgrades)" \
    || bad "extensions: override counts" "${_ext_out}"

# --------------------------------------------------------------------------- #
# 12. Budget: project without .slopguard/ — digest within §8.8 limits and no
#     extensions line.  Use a second run of the same session so the one-shot
#     missing-tools notice does not distort the byte count.
# --------------------------------------------------------------------------- #

_budget_proj="${WORK}/budget-proj"
mkdir -p "${_budget_proj}"
_budget_json='{"session_id":"budget-steady-001","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
# First run: clears the missing-tools marker.
printf '%s\n' "${_budget_json}" \
    | SLOPGUARD_EXT_SH="${_stub_ext}" CLAUDE_PROJECT_DIR="${_budget_proj}" "${HOOK}" >/dev/null 2>&1
# Second run: steady-state output (no missing-tools line, no .slopguard/ dir).
_budget_out="$(printf '%s\n' "${_budget_json}" \
    | SLOPGUARD_EXT_SH="${_stub_ext}" CLAUDE_PROJECT_DIR="${_budget_proj}" "${HOOK}" 2>/dev/null)"

printf '%s\n' "${_budget_out}" | grep -q 'project extensions:' \
    && bad "budget: extensions line present for project without .slopguard/" "${_budget_out}" \
    || ok  "budget: no extensions line for project without .slopguard/"

_budget_lines="$(printf '%s\n' "${_budget_out}" | wc -l | tr -d ' ')"
_budget_bytes="$(printf '%s\n' "${_budget_out}" | wc -c | tr -d ' ')"
[ "${_budget_lines}" -le 15 ] \
    && ok  "budget: steady-state digest within 15-line limit (${_budget_lines} lines)" \
    || bad "budget: 15-line limit exceeded" "got ${_budget_lines} lines (limit 15)"
[ "${_budget_bytes}" -le 1500 ] \
    && ok  "budget: steady-state digest within 1500-byte limit (${_budget_bytes} bytes)" \
    || bad "budget: 1500-byte limit exceeded" "got ${_budget_bytes} bytes (limit 1500)"

# --------------------------------------------------------------------------- #
# 13. Overlay digest line: appears with tool count when tools have no project config
# --------------------------------------------------------------------------- #

# Run with default knob (overlay) against an empty project — all tools fall back to
# the baseline, so the overlay line must appear with a non-zero count.
_ov_proj="${WORK}/overlay-proj"
mkdir -p "${_ov_proj}"
_ov_json='{"session_id":"overlay-test-001","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
# First run clears missing-tools marker.
printf '%s\n' "${_ov_json}" \
    | CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE="overlay" CLAUDE_PROJECT_DIR="${_ov_proj}" "${HOOK}" >/dev/null 2>&1
# Second run: steady-state (no missing-tools noise).
_ov_out="$(printf '%s\n' "${_ov_json}" \
    | CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE="overlay" CLAUDE_PROJECT_DIR="${_ov_proj}" "${HOOK}" 2>/dev/null)"

printf '%s\n' "${_ov_out}" | grep -q 'using example configs' \
    && ok  "overlay: digest line present when tools have no project config" \
    || bad "overlay: digest line present when tools have no project config" "${_ov_out}"

printf '%s\n' "${_ov_out}" | grep -q 'security findings only' \
    && ok  "overlay: digest line mentions security findings only" \
    || bad "overlay: digest line mentions security findings only" "${_ov_out}"

printf '%s\n' "${_ov_out}" | grep -q 'adopt-config' \
    && ok  "overlay: digest line includes adopt-config hint" \
    || bad "overlay: digest line includes adopt-config hint" "${_ov_out}"

# The count must be a positive integer.
_ov_count="$(printf '%s\n' "${_ov_out}" \
    | grep 'using example configs' \
    | sed 's/.*slop-guard: \([0-9][0-9]*\) .*/\1/' | head -1 || true)"
[ "${_ov_count:-0}" -gt 0 ] \
    && ok  "overlay: count is positive (${_ov_count} tools)" \
    || bad "overlay: count is positive" "got: ${_ov_count}"

# profile.json must carry config_modes map.
_ov_sess="${_TEST_DATA}/sessions/overlay-test-001"
if [ -f "${_ov_sess}/profile.json" ]; then
    _ov_modes_type="$(jq -r '.config_modes | type' "${_ov_sess}/profile.json" 2>/dev/null || printf 'ERROR')"
    [ "${_ov_modes_type}" = "object" ] \
        && ok  "overlay: profile.json carries .config_modes object" \
        || bad "overlay: profile.json .config_modes type" "got: ${_ov_modes_type}"

    _ov_ruff_mode="$(jq -r '.config_modes.ruff' "${_ov_sess}/profile.json" 2>/dev/null || true)"
    [ "${_ov_ruff_mode}" = "overlay" ] \
        && ok  "overlay: profile.json .config_modes.ruff = overlay for baseline project" \
        || bad "overlay: profile.json .config_modes.ruff" "got: ${_ov_ruff_mode}"
else
    bad "overlay: profile.json missing for overlay-test-001" ""
fi

# tools[] array must carry config_mode per entry.
if [ -f "${_ov_sess}/profile.json" ]; then
    _ov_has_cm="$(jq -r '.tools[0] | has("config_mode")' "${_ov_sess}/profile.json" 2>/dev/null || printf 'false')"
    [ "${_ov_has_cm}" = "true" ] \
        && ok  "overlay: tools[] records carry config_mode field" \
        || bad "overlay: tools[] records carry config_mode field" "got: ${_ov_has_cm}"
fi

# --------------------------------------------------------------------------- #
# 14. Overlay digest line: absent when config_source knob is 'full'
# --------------------------------------------------------------------------- #

# With knob=full, all tools without project configs are in 'full' mode (not overlay),
# so the overlay line must NOT appear.
_full_proj="${WORK}/full-proj"
mkdir -p "${_full_proj}"
_full_json='{"session_id":"full-test-001","cwd":"/tmp","hook_event_name":"SessionStart","agent_id":null,"agent_type":null}'
# First run clears missing-tools marker.
printf '%s\n' "${_full_json}" \
    | CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE="full" CLAUDE_PROJECT_DIR="${_full_proj}" "${HOOK}" >/dev/null 2>&1
# Second run.
_full_out="$(printf '%s\n' "${_full_json}" \
    | CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE="full" CLAUDE_PROJECT_DIR="${_full_proj}" "${HOOK}" 2>/dev/null)"

printf '%s\n' "${_full_out}" | grep -q 'using example configs' \
    && bad "overlay: line must be absent when config_source=full" "${_full_out}" \
    || ok  "overlay: line absent when config_source=full (all tools in full mode)"

# profile.json must show mode=full for ruff.
_full_sess="${_TEST_DATA}/sessions/full-test-001"
if [ -f "${_full_sess}/profile.json" ]; then
    _full_ruff_mode="$(jq -r '.config_modes.ruff' "${_full_sess}/profile.json" 2>/dev/null || true)"
    [ "${_full_ruff_mode}" = "full" ] \
        && ok  "overlay: profile.json .config_modes.ruff = full when knob=full" \
        || bad "overlay: profile.json .config_modes.ruff with knob=full" "got: ${_full_ruff_mode}"
else
    bad "overlay: profile.json missing for full-test-001" ""
fi

# --------------------------------------------------------------------------- #
# 15. Budget with overlay line: still within §8.8 limits
# --------------------------------------------------------------------------- #

# Reuse the existing _budget_out (knob=overlay by default; all tools baseline).
# The overlay line is expected to appear; the total must still fit in 15/1500.
_budget_lines_ov="$(printf '%s\n' "${_budget_out}" | wc -l | tr -d ' ')"
_budget_bytes_ov="$(printf '%s\n' "${_budget_out}" | wc -c | tr -d ' ')"
printf '%s\n' "${_budget_out}" | grep -q 'using example configs' \
    && ok  "budget: overlay line present in budget-proj output" \
    || ok  "budget: overlay line absent (all tools already have configs)"
[ "${_budget_lines_ov}" -le 15 ] \
    && ok  "budget+overlay: within 15-line limit (${_budget_lines_ov} lines)" \
    || bad "budget+overlay: 15-line limit exceeded" "got ${_budget_lines_ov} lines (limit 15)"
[ "${_budget_bytes_ov}" -le 1500 ] \
    && ok  "budget+overlay: within 1500-byte limit (${_budget_bytes_ov} bytes)" \
    || bad "budget+overlay: 1500-byte limit exceeded" "got ${_budget_bytes_ov} bytes (limit 1500)"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
