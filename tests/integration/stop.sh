#!/usr/bin/env bash
# tests/integration/stop.sh — stop-gate integration tests.
# Sourced by tests/tool-integration after the helper API (it_*) is defined.
#
# Coverage (bad fixture → mapped AP-id via hooks/stop; good fixture → no finding):
#   psalm   — TaintedSql from $_GET → PDO::query → AP-PHP-SEC-001  (balanced: blocker)
#   checkov — CKV_AWS_57 dir scan  → AP-IaC-SEC-001               (balanced: blocker)
#
# Notes
# -----
# The stop-gate path (hooks/stop) differs from medium-tier (bin/slopguard post-write);
# it_run is not used here.  _it_stop_run drives hooks/stop directly, mirroring the
# pattern in tests/stop_test.sh.
#
# psalm:   Uses PHP builtins (PDO) only — no vendor/ required.  A minimal psalm.xml
#          is created in each project directory so the baseline psalm.xml (which has
#          ${SLOPGUARD_CACHE_DIR}/psalm) is not consulted.
#          it_skip_unless_tool psalm symlinks the psalm binary into the project
#          vendor/bin/ so resolve_tool finds it via project-first resolution.
#
# checkov: stop-gate runs checkov with -d (directory scan), not -f (single file).
#          All stop-gate checkov findings carry ap_id = "AP-IaC-SEC-001" (hardcoded
#          in _stop_run_checkov; different from medium-tier which uses the mapping YAML).

# Ensure session directory root exists (runner exports _IT_WORK but does not
# pre-create plugin-data/sessions/).
_IT_STOP_PDATA="${_IT_WORK}/plugin-data"
mkdir -p "${_IT_STOP_PDATA}/sessions"

# --------------------------------------------------------------------------- #
# Local helpers
# --------------------------------------------------------------------------- #

# _it_stop_setup_sess <session_id>
# Create a fresh, empty session state for hooks/stop.
_it_stop_setup_sess() {
    local _sess="$1"
    local _sdir="${_IT_STOP_PDATA}/sessions/${_sess}"
    mkdir -p "$_sdir"
    printf '[]\n'  > "${_sdir}/findings.json"
    printf '0\n'   > "${_sdir}/stop-iterations"
    printf '{}\n'  > "${_sdir}/profile.json"
    printf '[]\n'  > "${_sdir}/docs-lookups.json"
    printf '{}\n'  > "${_sdir}/touched.json"
}

# _it_stop_run <project_dir>
# Invoke hooks/stop with a normal Stop payload; print combined stdout+stderr.
# Creates and cleans up its own session so runs are independent.
_it_stop_run() {
    local _proj="$1"
    local _sess; _sess="sg-it-stop-${$}-${RANDOM:-0}"
    _it_stop_setup_sess "$_sess"

    local _payload
    _payload="$(printf \
        '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false,"agent_id":null}' \
        "$_sess" "$_proj")"

    printf '%s' "$_payload" | \
        CLAUDE_PROJECT_DIR="$_proj" \
        CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$_IT_STOP_PDATA}" \
        CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=balanced \
        CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK="false" \
        CLAUDE_PLUGIN_OPTION_REQUIRE_DOCS_LOOKUP="false" \
        CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="$([ "${SLOPGUARD_IT_DEBUG:-0}" = "1" ] && printf 'project-first' || printf '%s' "${CLAUDE_PLUGIN_OPTION_TOOL_SOURCE:-project-first}")" \
        "${PLUGIN_ROOT}/hooks/stop" 2>&1 || true

    rm -rf "${_IT_STOP_PDATA}/sessions/${_sess}" 2>/dev/null || true
}

# _it_stop_noap <output> <AP-ID> <label>
# Assert the AP-ID is absent from the stop-gate output; record ok/bad.
# (it_expect_silent checks for '"additionalContext"' which the stop-gate ALWAYS
# emits even for the "no findings" case; this check is more targeted.)
_it_stop_noap() {
    local _out="$1" _apid="$2" _label="$3"
    case "$_out" in
        *"${_apid}"*)
            printf '  FAIL  %s: unexpected %s in stop-gate output\n' "$_label" "$_apid"
            FAIL=$((FAIL + 1))
            ;;
        *)
            printf '  ok    %s\n' "$_label"
            PASS=$((PASS + 1))
            ;;
    esac
}

# =========================================================================== #
# 1. psalm — TaintedSql → AP-PHP-SEC-001
# =========================================================================== #
# $_GET['id'] flows untouched into PDO::query() — psalm taint analysis detects
# TaintedSql.  PDO is a PHP builtin; no vendor/ is needed for this analysis.
# A project-local psalm.xml (no cacheDirectory attribute) avoids the
# ${SLOPGUARD_CACHE_DIR} expansion that the baseline psalm.xml uses.
#
# _stop_run_psalm filters findings by basename of changed PHP files.  The test
# file is untracked → picked up by git ls-files --others in _stop_diff_files.

it_project "psalm-stop-bad"
_it_psalm_bad="$_IT_CUR_PROJ"
if it_skip_unless_tool psalm; then
    cat > "${_it_psalm_bad}/psalm.xml" <<'ENDXML'
<?xml version="1.0"?>
<psalm errorLevel="1" xmlns="https://getpsalm.org/schema/config">
    <projectFiles>
        <directory name="src"/>
    </projectFiles>
</psalm>
ENDXML
    mkdir -p "${_it_psalm_bad}/src"
    cat > "${_it_psalm_bad}/src/bad.php" <<'ENDPHP'
<?php
/**
 * Tainted SQL: $_GET['id'] flows to PDO::query() — TaintedSql → AP-PHP-SEC-001.
 * search() is called at script level so psalm's interprocedural taint analysis
 * traces the path from $_GET (source) to PDO::query (sink).  A function that
 * is defined but never called is unreachable dead code; psalm 6.x does not
 * report taint flows through unreachable functions.
 * Reference: psalm.dev/docs/security_analysis — "data flows through your application".
 */
function search(): void
{
    $id  = $_GET['id'];
    $pdo = new \PDO('sqlite::memory:');
    $pdo->query("SELECT * FROM users WHERE id = {$id}");
}
search();
ENDPHP
    # src/bad.php is untracked: _stop_diff_files picks it up via git ls-files --others.

    _it_psalm_bad_out="$(_it_stop_run "${_it_psalm_bad}")"
    it_expect_ap "$_it_psalm_bad_out" "AP-PHP-SEC-001" \
        "psalm stop-gate: TaintedSql → AP-PHP-SEC-001"

    # Good: parameterised query with no tainted source — no TaintedSql finding.
    it_project "psalm-stop-good"
    _it_psalm_good="$_IT_CUR_PROJ"
    it_skip_unless_tool psalm  # re-symlinks psalm into new project; never skips here

    cat > "${_it_psalm_good}/psalm.xml" <<'ENDXML'
<?xml version="1.0"?>
<psalm errorLevel="1" xmlns="https://getpsalm.org/schema/config">
    <projectFiles>
        <directory name="src"/>
    </projectFiles>
</psalm>
ENDXML
    mkdir -p "${_it_psalm_good}/src"
    cat > "${_it_psalm_good}/src/good.php" <<'ENDPHP'
<?php
/**
 * Parameterised query — no tainted SQL sink; no TaintedSql finding.
 */
function searchSafe(string $id): void
{
    $pdo  = new \PDO('sqlite::memory:');
    $stmt = $pdo->prepare('SELECT * FROM users WHERE id = ?');
    $stmt->execute([$id]);
}
ENDPHP

    _it_psalm_good_out="$(_it_stop_run "${_it_psalm_good}")"
    _it_stop_noap "$_it_psalm_good_out" "AP-PHP-SEC-001" \
        "psalm stop-gate: parameterised query produces no TaintedSql"
fi

# =========================================================================== #
# 2. checkov dir scan — CKV_AWS_57 (public S3 ACL) → AP-IaC-SEC-001
# =========================================================================== #
# _stop_run_checkov finds IaC dirs from the session diff (via _stop_iac_dirs),
# then runs checkov with -d on each directory.  All stop-gate checkov findings
# use the hardcoded ap_id "AP-IaC-SEC-001" (stop.sh does not consult the
# mapping YAML; that is intentional — the stop-gate is a coarser gate).
#
# The bad fixture (main.tf with acl = "public-read") is untracked.
# _stop_diff_files picks it up via git ls-files --others; _stop_iac_dirs
# extracts "." (dirname of main.tf); checkov runs on the project root.

it_project "checkov-stop-bad"
_it_ckv_stop_bad="$_IT_CUR_PROJ"
if it_skip_unless_tool checkov; then
    cp "${_IT_FIXTURES}/terraform/bad/main.tf" "${_it_ckv_stop_bad}/main.tf"

    _it_ckv_stop_bad_out="$(_it_stop_run "${_it_ckv_stop_bad}")"
    it_expect_ap "$_it_ckv_stop_bad_out" "AP-IaC-SEC-001" \
        "checkov stop-gate: CKV_AWS_57 dir scan → AP-IaC-SEC-001"

    # Good: compliant TF (has required_version, no resources) — no CKV findings.
    it_project "checkov-stop-good"
    _it_ckv_stop_good="$_IT_CUR_PROJ"
    it_skip_unless_tool checkov  # re-symlinks; never skips here

    cp "${_IT_FIXTURES}/terraform/good/main.tf" "${_it_ckv_stop_good}/main.tf"

    _it_ckv_stop_good_out="$(_it_stop_run "${_it_ckv_stop_good}")"
    _it_stop_noap "$_it_ckv_stop_good_out" "AP-IaC-SEC-001" \
        "checkov stop-gate: compliant TF produces no finding"
fi
