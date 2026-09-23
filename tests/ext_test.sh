#!/usr/bin/env bash
# ext_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.
#
# Covers the acceptance criteria for the project-scoped extension mechanism:
#   1. Descriptor with project binary → finding carries the project AP id.
#   2. Binary absent → no finding, exit 0.
#   3. resolve.path_sha256 mismatch → refused:sha256-mismatch, tool skipped.
#   4. Neither resolution field → refused:no-resolution.
#   5. Name collision with tools.lock.json → refused:pinned-tool-collision.
#   6. run.args metacharacters arrive as literal argv elements.
#   7. Mapping override: ext_override_counts reports correct total + downgrades.
#   8. Unmapped rule id → neutral default (severity=warn, category=maintainability).
#   9. Malformed descriptor → refused, run does not abort.

# --------------------------------------------------------------------------- #
# Setup
# --------------------------------------------------------------------------- #

_ET_WORK="${TMPDIR:-/tmp}/slop-guard-ext-$$"
mkdir -p "$_ET_WORK"
trap 'rm -rf "$_ET_WORK"' EXIT INT TERM

# Source ext.sh (dispatch.sh is already sourced by dispatch_test.sh above us).
# shellcheck source=../lib/ext.sh
. "${PLUGIN_ROOT}/lib/ext.sh"

# Re-use the CLAUDE_PLUGIN_DATA set up by dispatch_test.sh (or create our own).
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
    export CLAUDE_PLUGIN_DATA="${_ET_WORK}/plugin-data"
    mkdir -p "${CLAUDE_PLUGIN_DATA}/sessions"
fi

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

_et_make_git_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q 2>/dev/null
    git -C "$dir" config user.email "test@slopguard.test" 2>/dev/null
    git -C "$dir" config user.name  "Slop Guard Test"     2>/dev/null
}

_et_commit() {
    local dir="$1" fname="$2" content="$3"
    printf '%s\n' "$content" > "${dir}/${fname}"
    git -C "$dir" add "$fname"             2>/dev/null
    git -C "$dir" commit -q -m "add $fname" 2>/dev/null
}

_et_count_findings() {
    local tmp="$1"
    [ -f "$tmp" ] || { printf '0'; return; }
    local n; n="$(wc -l < "$tmp" 2>/dev/null)"
    printf '%s' "${n// /}"
}

# Write a descriptor YAML.
# Usage: _et_write_desc <dir> <name> [extra_yaml_lines...]
_et_write_desc() {
    local dir="$1" name="$2"
    shift 2
    mkdir -p "${dir}/.slopguard/tools"
    # Caller supplies the full descriptor body via stdin or arguments.
    cat > "${dir}/.slopguard/tools/${name}.yaml"
}

# Write a project mapping override YAML.
_et_write_mapping() {
    local dir="$1" tool="$2"
    shift 2
    mkdir -p "${dir}/.slopguard/mapping"
    cat > "${dir}/.slopguard/mapping/${tool}.yaml"
}

# Run dispatch_fast, return the temp findings file path.
_et_run_dispatch() {
    local project_dir="$1" file="$2" session_id="$3" agent_id="${4:---}"
    local tmp; tmp="$(mktemp "${_ET_WORK}/.findings.XXXXXX")"
    CLAUDE_PROJECT_DIR="$project_dir" \
        dispatch_fast "$file" "$session_id" "$agent_id" "$project_dir" "$tmp" \
        2>/dev/null || true
    printf '%s' "$tmp"
}

# --------------------------------------------------------------------------- #
# 1. Descriptor with project binary produces finding with project AP id
# --------------------------------------------------------------------------- #

_et_p1="${_ET_WORK}/proj-ok"
_et_make_git_repo "$_et_p1"
_et_commit "$_et_p1" "query.sql" "SELECT 1"
printf 'SELECT * FROM users WHERE id = 1\n' > "${_et_p1}/query.sql"  # unstaged change

mkdir -p "${_et_p1}/.venv/bin" "${_et_p1}/.slopguard/tools"
# Stub binary: outputs JSON with one finding for rule TSQL-001.
_et_stub_out='[{"code":"TSQL-001","message":"Unsafe query","line_no":1}]'
_et_stub_data="${_ET_WORK}/.stub-data-sqltool"
printf '%s' "$_et_stub_out" > "$_et_stub_data"
printf '#!/bin/sh\ncat "%s"\n' "$_et_stub_data" > "${_et_p1}/.venv/bin/sqltool"
chmod +x "${_et_p1}/.venv/bin/sqltool"

# Descriptor.
cat > "${_et_p1}/.slopguard/tools/sqltool.yaml" << 'YAML'
name: sqltool
tier: fast
match:
  globs: ["**/*.sql"]
resolve:
  project: [".venv/bin/sqltool"]
run:
  args: ["check", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[] | {rule: .code, line: .line_no, message: .message}'
YAML

# Project mapping override: TSQL-001 → AP-SQL-TEST-001, error.
mkdir -p "${_et_p1}/.slopguard/mapping"
cat > "${_et_p1}/.slopguard/mapping/sqltool.yaml" << 'YAML'
rules:
  TSQL-001:
    ap_id: AP-SQL-TEST-001
    severity: error
    category: security
    cwe: ""
YAML

_et_sess1="et-ok-$$"
_et_tmp1="$(_et_run_dispatch "$_et_p1" "${_et_p1}/query.sql" "$_et_sess1")"
_et_n1="$(_et_count_findings "$_et_tmp1")"
[ "$_et_n1" -ge 1 ] \
    && ok  "ext: descriptor with project binary produces a finding" \
    || bad "ext: descriptor with project binary" "expected >=1 finding, got ${_et_n1}"

# Check the finding carries the project AP id.
_et_ap1="$(jq -r '.[0].ap_id // empty' \
    "$(state_dir "$_et_sess1" "--")/findings.json" 2>/dev/null || true)"
[ "$_et_ap1" = "AP-SQL-TEST-001" ] \
    && ok  "ext: finding carries project AP id (AP-SQL-TEST-001)" \
    || bad "ext: finding ap_id" "expected AP-SQL-TEST-001, got '${_et_ap1}'"

# --------------------------------------------------------------------------- #
# 2. Binary absent → no finding, exit 0
# --------------------------------------------------------------------------- #

_et_p2="${_ET_WORK}/proj-absent"
_et_make_git_repo "$_et_p2"
_et_commit "$_et_p2" "query.sql" "SELECT 1"
printf 'SELECT * FROM t WHERE id = 1\n' > "${_et_p2}/query.sql"

# Same descriptor, but .venv/bin/sqltool does NOT exist.
mkdir -p "${_et_p2}/.slopguard/tools"
cp "${_et_p1}/.slopguard/tools/sqltool.yaml" "${_et_p2}/.slopguard/tools/sqltool.yaml"

_et_sess2="et-absent-$$"
_et_tmp2="$(_et_run_dispatch "$_et_p2" "${_et_p2}/query.sql" "$_et_sess2")"
_et_n2="$(_et_count_findings "$_et_tmp2")"
[ "$_et_n2" -eq 0 ] \
    && ok  "ext: absent binary → no finding" \
    || bad "ext: absent binary" "expected 0 findings, got ${_et_n2}"

# Also verify ext_tools reports status=absent, not an error.
_et_status2="$(SLOPGUARD_EXT_DIR="${_et_p2}/.slopguard" ext_tools "$_et_p2" \
    | jq -r '.status' 2>/dev/null)"
[ "$_et_status2" = "absent" ] \
    && ok  "ext: absent binary → ext_tools status=absent" \
    || bad "ext: absent binary status" "expected absent, got '${_et_status2}'"

# --------------------------------------------------------------------------- #
# 3. resolve.path_sha256 mismatch → refused:sha256-mismatch
# --------------------------------------------------------------------------- #

_et_p3="${_ET_WORK}/proj-sha-mismatch"
mkdir -p "${_et_p3}/.slopguard/tools"

# Put a binary named "sqltool3" on PATH (via a temp dir in PATH).
_et_path3_dir="${_ET_WORK}/path3bin"
mkdir -p "$_et_path3_dir"
printf '#!/bin/sh\nprintf '"'"'[]'"'"'\n' > "${_et_path3_dir}/sqltool3"
chmod +x "${_et_path3_dir}/sqltool3"

cat > "${_et_p3}/.slopguard/tools/sqltool3.yaml" << 'YAML'
name: sqltool3
tier: fast
match:
  globs: ["**/*.sql"]
resolve:
  path_sha256: "0000000000000000000000000000000000000000000000000000000000000000"
run:
  args: ["check", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[]'
YAML

_et_status3="$(PATH="${_et_path3_dir}:${PATH}" \
    SLOPGUARD_EXT_DIR="${_et_p3}/.slopguard" \
    ext_tools "$_et_p3" | jq -r '.status' 2>/dev/null)"
[ "$_et_status3" = "refused:sha256-mismatch" ] \
    && ok  "ext: sha256 mismatch → refused:sha256-mismatch" \
    || bad "ext: sha256 mismatch" "expected refused:sha256-mismatch, got '${_et_status3}'"

# Verify the tool does NOT run (no findings directory created under this session).
_et_p3_repo="${_ET_WORK}/proj-sha-mismatch-repo"
_et_make_git_repo "$_et_p3_repo"
_et_commit "$_et_p3_repo" "q.sql" "SELECT 1"
cp -r "${_et_p3}/.slopguard" "${_et_p3_repo}/.slopguard"
_et_sess3="et-sha-$$"
_et_tmp3="$(mktemp "${_ET_WORK}/.findings.XXXXXX")"
PATH="${_et_path3_dir}:${PATH}" \
    SLOPGUARD_EXT_DIR="${_et_p3_repo}/.slopguard" \
    dispatch_fast "${_et_p3_repo}/q.sql" "$_et_sess3" "--" \
        "$_et_p3_repo" "$_et_tmp3" 2>/dev/null || true
_et_n3="$(_et_count_findings "$_et_tmp3")"
[ "$_et_n3" -eq 0 ] \
    && ok  "ext: sha256 mismatch → tool does not run" \
    || bad "ext: sha256 mismatch tool skipped" "expected 0, got ${_et_n3}"

# --------------------------------------------------------------------------- #
# 4. Neither resolution field → refused:no-resolution
# --------------------------------------------------------------------------- #

_et_p4="${_ET_WORK}/proj-no-res"
mkdir -p "${_et_p4}/.slopguard/tools"
cat > "${_et_p4}/.slopguard/tools/noresolver.yaml" << 'YAML'
name: noresolver
tier: fast
match:
  globs: ["**/*.sql"]
resolve:
  project: []
run:
  args: ["check", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[]'
YAML

_et_status4="$(SLOPGUARD_EXT_DIR="${_et_p4}/.slopguard" \
    ext_tools "$_et_p4" | jq -r '.status' 2>/dev/null)"
[ "$_et_status4" = "refused:no-resolution" ] \
    && ok  "ext: no resolution fields → refused:no-resolution" \
    || bad "ext: no resolution" "expected refused:no-resolution, got '${_et_status4}'"

# --------------------------------------------------------------------------- #
# 5. Name collision with tools.lock.json → refused:pinned-tool-collision
# --------------------------------------------------------------------------- #

_et_p5="${_ET_WORK}/proj-collision"
mkdir -p "${_et_p5}/.slopguard/tools"
cat > "${_et_p5}/.slopguard/tools/ruff.yaml" << 'YAML'
name: ruff
tier: fast
match:
  globs: ["**/*.py"]
resolve:
  project: [".venv/bin/ruff"]
run:
  args: ["check", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[]'
YAML

_et_status5="$(SLOPGUARD_EXT_DIR="${_et_p5}/.slopguard" \
    ext_tools "$_et_p5" | jq -r '.status' 2>/dev/null)"
[ "$_et_status5" = "refused:pinned-tool-collision" ] \
    && ok  "ext: pinned tool name → refused:pinned-tool-collision" \
    || bad "ext: pinned-tool-collision" "expected refused:pinned-tool-collision, got '${_et_status5}'"

# --------------------------------------------------------------------------- #
# 6. run.args metacharacters arrive as literal argv elements
# --------------------------------------------------------------------------- #

_et_p6="${_ET_WORK}/proj-meta"
_et_make_git_repo "$_et_p6"
_et_commit "$_et_p6" "data.sql" "SELECT 1"
printf 'SELECT * FROM t\n' > "${_et_p6}/data.sql"

mkdir -p "${_et_p6}/.venv/bin" "${_et_p6}/.slopguard/tools"

_et_meta_args_file="${_ET_WORK}/meta-args.txt"
# Stub records its argv (one arg per line) and outputs empty JSON array.
cat > "${_et_p6}/.venv/bin/metatool" << STUBEOF
#!/bin/sh
printf '%s\n' "\$@" > "${_et_meta_args_file}"
printf '[]'
STUBEOF
chmod +x "${_et_p6}/.venv/bin/metatool"

cat > "${_et_p6}/.slopguard/tools/metatool.yaml" << 'YAML'
name: metatool
tier: fast
match:
  globs: ["**/*.sql"]
resolve:
  project: [".venv/bin/metatool"]
run:
  args: [";", "$(echo hi)", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[]'
YAML

_et_sess6="et-meta-$$"
_et_tmp6="$(_et_run_dispatch "$_et_p6" "${_et_p6}/data.sql" "$_et_sess6")"

# Read the recorded args.
_et_arg0="$(sed -n '1p' "$_et_meta_args_file" 2>/dev/null || true)"
_et_arg1="$(sed -n '2p' "$_et_meta_args_file" 2>/dev/null || true)"
_et_arg2="$(sed -n '3p' "$_et_meta_args_file" 2>/dev/null || true)"

[ "$_et_arg0" = ';' ] \
    && ok  "ext: metachar ';' arrives as literal argv element" \
    || bad "ext: metachar ';'" "expected ';', got '${_et_arg0}'"

[ "$_et_arg1" = '$(echo hi)' ] \
    && ok  "ext: metachar '\$(echo hi)' arrives as literal argv element" \
    || bad "ext: metachar subshell" "expected '\$(echo hi)', got '${_et_arg1}'"

[ "$_et_arg2" = "${_et_p6}/data.sql" ] \
    && ok  "ext: {file} substituted to absolute path" \
    || bad "ext: {file} substitution" "expected ${_et_p6}/data.sql, got '${_et_arg2}'"

# --------------------------------------------------------------------------- #
# 7. Mapping override: ext_override_counts reports 2 1
# --------------------------------------------------------------------------- #
# Use the real ruff mapping (plugin): S608=blocker, T201=warn.
# Project override: S608→warn (downgrade), T201→error (upgrade).

_et_p7="${_ET_WORK}/proj-overrides"
mkdir -p "${_et_p7}/.slopguard/mapping"
cat > "${_et_p7}/.slopguard/mapping/ruff.yaml" << 'YAML'
rules:
  S608:
    severity: warn
  T201:
    severity: error
YAML

_et_counts="$(SLOPGUARD_EXT_DIR="${_et_p7}/.slopguard" ext_override_counts "$_et_p7")"
[ "$_et_counts" = "2 1" ] \
    && ok  "ext: override_counts reports 2 overrides, 1 downgrade" \
    || bad "ext: override_counts" "expected '2 1', got '${_et_counts}'"

# --------------------------------------------------------------------------- #
# 8. Unmapped rule id → finding with neutral default (warn / maintainability)
# --------------------------------------------------------------------------- #

_et_p8="${_ET_WORK}/proj-unmapped"
_et_make_git_repo "$_et_p8"
_et_commit "$_et_p8" "query.sql" "SELECT 1"
printf 'SELECT * FROM t\n' > "${_et_p8}/query.sql"

mkdir -p "${_et_p8}/.venv/bin" "${_et_p8}/.slopguard/tools"

# Stub reports an unknown rule UNMAPPED-999.
_et_stub8_out='[{"code":"UNMAPPED-999","message":"Some warning","line_no":1}]'
_et_stub8_data="${_ET_WORK}/.stub-data-unmapped"
printf '%s' "$_et_stub8_out" > "$_et_stub8_data"
printf '#!/bin/sh\ncat "%s"\n' "$_et_stub8_data" > "${_et_p8}/.venv/bin/unmaptool"
chmod +x "${_et_p8}/.venv/bin/unmaptool"

cat > "${_et_p8}/.slopguard/tools/unmaptool.yaml" << 'YAML'
name: unmaptool
tier: fast
match:
  globs: ["**/*.sql"]
resolve:
  project: [".venv/bin/unmaptool"]
run:
  args: ["check", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[] | {rule: .code, line: .line_no, message: .message}'
YAML

# No .slopguard/mapping/unmaptool.yaml — rule is entirely unknown.
_et_sess8="et-unmapped-$$"
_et_tmp8="$(_et_run_dispatch "$_et_p8" "${_et_p8}/query.sql" "$_et_sess8")"
_et_n8="$(_et_count_findings "$_et_tmp8")"
[ "$_et_n8" -ge 1 ] \
    && ok  "ext: unmapped rule still produces a finding" \
    || bad "ext: unmapped rule finding" "expected >=1, got ${_et_n8}"

_et_f8="$(state_dir "$_et_sess8" "--")/findings.json"
_et_sev8="$(jq -r '.[0].severity // empty' "$_et_f8" 2>/dev/null || true)"
_et_cat8="$(jq -r '.[0].category // empty' "$_et_f8" 2>/dev/null || true)"
[ "$_et_sev8" = "warn" ] \
    && ok  "ext: unmapped rule gets neutral severity=warn" \
    || bad "ext: unmapped rule severity" "expected warn, got '${_et_sev8}'"
[ "$_et_cat8" = "maintainability" ] \
    && ok  "ext: unmapped rule gets neutral category=maintainability" \
    || bad "ext: unmapped rule category" "expected maintainability, got '${_et_cat8}'"

# --------------------------------------------------------------------------- #
# 9. Malformed descriptor → refused with reason, no abort
# --------------------------------------------------------------------------- #

_et_p9="${_ET_WORK}/proj-malformed"
mkdir -p "${_et_p9}/.slopguard/tools"

# Missing required fields (no tier, no args, no jq).
cat > "${_et_p9}/.slopguard/tools/badtool.yaml" << 'YAML'
name: badtool
match:
  globs: ["**/*.sql"]
resolve:
  project: [".venv/bin/badtool"]
YAML

_et_bad_status="$(SLOPGUARD_EXT_DIR="${_et_p9}/.slopguard" \
    ext_tools "$_et_p9" | jq -r '.status' 2>/dev/null)"
case "$_et_bad_status" in
    refused:*)
        ok  "ext: malformed descriptor → refused:* (got: ${_et_bad_status})"
        ;;
    *)
        bad "ext: malformed descriptor refused" "expected refused:*, got '${_et_bad_status}'"
        ;;
esac

# Also verify dispatch_fast does not abort when a malformed descriptor is present.
_et_p9_repo="${_ET_WORK}/proj-malformed-repo"
_et_make_git_repo "$_et_p9_repo"
_et_commit "$_et_p9_repo" "data.sql" "SELECT 1"
cp -r "${_et_p9}/.slopguard" "${_et_p9_repo}/.slopguard"
_et_exit9=0
_et_tmp9="$(mktemp "${_ET_WORK}/.findings.XXXXXX")"
SLOPGUARD_EXT_DIR="${_et_p9_repo}/.slopguard" \
    dispatch_fast "${_et_p9_repo}/data.sql" "et-bad-$$" "--" \
        "$_et_p9_repo" "$_et_tmp9" 2>/dev/null || _et_exit9=$?
[ "$_et_exit9" -eq 0 ] \
    && ok  "ext: malformed descriptor → dispatch_fast still exits 0" \
    || bad "ext: malformed no abort" "exit code: ${_et_exit9}"

# --------------------------------------------------------------------------- #
# 10. Wiring: the real hook path runs descriptors.
#
# dispatch_fast only reaches descriptors when lib/ext.sh has been sourced, so a
# test that sources ext.sh itself cannot prove the shipped path works. This runs
# bin/slopguard post-write, which is what the PostToolUse hook actually invokes.
# --------------------------------------------------------------------------- #

_et_p10="${_ET_WORK}/proj-hook"
_et_make_git_repo "$_et_p10"
mkdir -p "${_et_p10}/.venv/bin" "${_et_p10}/.slopguard/tools" "${_et_p10}/.slopguard/mapping"
cat > "${_et_p10}/.venv/bin/hooktool" <<'STUB'
#!/usr/bin/env bash
printf '[{"code":"HT01","line_no":2,"message":"hook path reached"}]\n'
STUB
chmod +x "${_et_p10}/.venv/bin/hooktool"
cat > "${_et_p10}/.slopguard/tools/hooktool.yaml" <<'DESC'
name: hooktool
tier: fast
match:
  globs: ["**/*.sql"]
run:
  args: ["lint", "{file}"]
  timeout: 8
parse:
  format: json
  jq: '.[] | {rule: .code, line: .line_no, message: .message}'
resolve:
  project: [".venv/bin/hooktool"]
DESC
cat > "${_et_p10}/.slopguard/mapping/hooktool.yaml" <<'MAP'
rules:
  HT01:
    ap_id: AP-SQL-MAINT-002
    severity: warn
    category: maintainability
    cwe: ""
MAP
_et_commit "$_et_p10" "hook.sql" "SELECT 1"
printf 'SELECT 1;\nSELECT * FROM t;\n' > "${_et_p10}/hook.sql"
_et_data10="${_ET_WORK}/data-hook"
_et_out10="$(jq -n --arg f "${_et_p10}/hook.sql" \
    '{session_id:"et-hook",agent_id:"--",tool_name:"Write",tool_input:{file_path:$f,content:"SELECT * FROM t;"}}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PLUGIN_DATA="$_et_data10" \
      CLAUDE_PROJECT_DIR="$_et_p10" "${PLUGIN_ROOT}/bin/slopguard" post-write --tier=fast 2>/dev/null)"
case "$_et_out10" in
    *AP-SQL-MAINT-002*)
        ok  "ext: descriptor runs through bin/slopguard post-write (hook path)" ;;
    *)
        bad "ext: descriptor via hook path" "no mapped finding in output: ${_et_out10:-<empty>}" ;;
esac
