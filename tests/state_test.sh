#!/usr/bin/env bash
# state_test.sh — tests for lib/state.sh and lib/finding.sh.
#
# Sourced by tests/run-tests; ok() and bad() are pre-defined there.
# Overrides CLAUDE_PLUGIN_DATA to an isolated temp directory so tests never
# touch real session state.

STATE_TEST_WORK="${TMPDIR:-/tmp}/slop-guard-state-test-$$"
export CLAUDE_PLUGIN_DATA="${STATE_TEST_WORK}/data"
mkdir -p "${CLAUDE_PLUGIN_DATA}/sessions"
trap 'rm -rf "${STATE_TEST_WORK}"' EXIT INT TERM

# shellcheck source=../lib/state.sh
. "${PLUGIN_ROOT}/lib/state.sh"
# shellcheck source=../lib/finding.sh
. "${PLUGIN_ROOT}/lib/finding.sh"

# --------------------------------------------------------------------------- #
# 1. state_dir: path construction
# --------------------------------------------------------------------------- #
val="$(state_dir "sess-123")"
[ "$val" = "${CLAUDE_PLUGIN_DATA}/sessions/sess-123" ] \
    && ok  "state_dir: no agent" || bad "state_dir: no agent" "$val"

val="$(state_dir "sess-123" "agent-abc")"
[ "$val" = "${CLAUDE_PLUGIN_DATA}/sessions/sess-123/agent-abc" ] \
    && ok  "state_dir: with agent_id" || bad "state_dir: with agent_id" "$val"

val="$(state_dir "sess-123" "--")"
[ "$val" = "${CLAUDE_PLUGIN_DATA}/sessions/sess-123" ] \
    && ok  "state_dir: '--' treated as no agent" \
    || bad "state_dir: '--' treated as no agent" "$val"

# --------------------------------------------------------------------------- #
# 2. state_init: creates directory and all required files
# --------------------------------------------------------------------------- #
state_init "init-test-session"
_sd="${CLAUDE_PLUGIN_DATA}/sessions/init-test-session"

[ -d "$_sd" ] \
    && ok  "state_init: directory created" || bad "state_init: directory" "missing"
[ -f "${_sd}/profile.json" ] \
    && ok  "state_init: profile.json" || bad "state_init: profile.json" "missing"
[ -f "${_sd}/touched.json" ] \
    && ok  "state_init: touched.json" || bad "state_init: touched.json" "missing"
[ -f "${_sd}/findings.json" ] \
    && ok  "state_init: findings.json" || bad "state_init: findings.json" "missing"
[ -f "${_sd}/stop-iterations" ] \
    && ok  "state_init: stop-iterations" || bad "state_init: stop-iterations" "missing"

# findings.json must be a valid empty JSON array
val="$(cat "${_sd}/findings.json" | tr -d '[:space:]')"
[ "$val" = "[]" ] \
    && ok  "state_init: findings.json is []" \
    || bad "state_init: findings.json content" "got: $val"

# stop-iterations must be 0
val="$(cat "${_sd}/stop-iterations" | tr -d '[:space:]')"
[ "$val" = "0" ] \
    && ok  "state_init: stop-iterations is 0" \
    || bad "state_init: stop-iterations content" "got: $val"

# --------------------------------------------------------------------------- #
# 3. state_init with agent_id
# --------------------------------------------------------------------------- #
state_init "agent-session" "agent-xyz"
[ -d "${CLAUDE_PLUGIN_DATA}/sessions/agent-session/agent-xyz" ] \
    && ok  "state_init: agent subdirectory created" \
    || bad "state_init: agent subdirectory" "missing"

# --------------------------------------------------------------------------- #
# 4. state_lock_acquire / state_lock_release
# --------------------------------------------------------------------------- #
_lock_dir="${CLAUDE_PLUGIN_DATA}/sessions/lock-test-basic"
mkdir -p "$_lock_dir"

state_lock_acquire "$_lock_dir" \
    && ok  "lock: acquire succeeds" || bad "lock: acquire" "failed"

[ -d "${_lock_dir}/.lock" ] \
    && ok  "lock: .lock directory exists while held" \
    || bad "lock: .lock directory" "missing"

state_lock_release "$_lock_dir"

[ ! -d "${_lock_dir}/.lock" ] \
    && ok  "lock: .lock removed after release" \
    || bad "lock: .lock removed" "still present"

# --------------------------------------------------------------------------- #
# 5. Stale lock is detected and removed; acquisition succeeds
# --------------------------------------------------------------------------- #
_stale_dir="${CLAUDE_PLUGIN_DATA}/sessions/stale-lock-test"
mkdir -p "$_stale_dir"
mkdir -p "${_stale_dir}/.lock"
# Backdate the lock to 90 seconds ago so it exceeds stale_age=60
touch -d '90 seconds ago' "${_stale_dir}/.lock" 2>/dev/null || true

state_lock_acquire "$_stale_dir" 10 60
_stale_rc=$?
state_lock_release "$_stale_dir"

[ "$_stale_rc" -eq 0 ] \
    && ok  "stale lock: acquisition succeeds after stale removal" \
    || bad "stale lock: acquisition" "rc=${_stale_rc} (stale lock not removed?)"

# --------------------------------------------------------------------------- #
# 6. finding_add: single finding, all fields
# --------------------------------------------------------------------------- #
state_init "finding-single"
finding_add "finding-single" "--" \
    "AP-TEST-001" "testtool" "test-rule" \
    "security" "blocker" '["CWE-89"]' \
    "app/main.py" "42" "42" \
    "SQL injection via request input" \
    "Use parameterised queries" "changed-lines" \
    "DB.query(user_input)"

_ff="${CLAUDE_PLUGIN_DATA}/sessions/finding-single/findings.json"
count="$(jq 'length' "$_ff")"
[ "$count" = "1" ] \
    && ok  "finding_add: single finding appended" \
    || bad "finding_add: count" "got: $count"

val="$(jq -r '.[0].ap_id' "$_ff")"
[ "$val" = "AP-TEST-001" ] \
    && ok  "finding_add: ap_id stored" || bad "finding_add: ap_id" "$val"

val="$(jq -r '.[0].tool' "$_ff")"
[ "$val" = "testtool" ] \
    && ok  "finding_add: tool stored" || bad "finding_add: tool" "$val"

val="$(jq -r '.[0].severity' "$_ff")"
[ "$val" = "blocker" ] \
    && ok  "finding_add: severity stored" || bad "finding_add: severity" "$val"

val="$(jq -r '.[0].cwe[0]' "$_ff")"
[ "$val" = "CWE-89" ] \
    && ok  "finding_add: cwe[0] stored" || bad "finding_add: cwe" "$val"

# Fingerprint: sha256:$(printf '%s|%s|%s|%s' tool tool_rule file snippet | sha256sum)
_expected_fp="sha256:$(printf '%s|%s|%s|%s' \
    "testtool" "test-rule" "app/main.py" "DB.query(user_input)" \
    | sha256sum | cut -d' ' -f1)"
val="$(jq -r '.[0].fingerprint' "$_ff")"
[ "$val" = "$_expected_fp" ] \
    && ok  "finding_add: fingerprint matches sha256(tool|rule|file|snippet)" \
    || bad "finding_add: fingerprint" "got=$val want=$_expected_fp"

# Snippet is NOT stored in the record
val="$(jq 'has("snippet")' "${_ff}" 2>/dev/null || echo false)"
# jq returns true/false for the array level; check per element
val="$(jq '.[0] | has("snippet")' "$_ff")"
[ "$val" = "false" ] \
    && ok  "finding_add: snippet not stored in record" \
    || bad "finding_add: snippet not stored" "got: $val"

# --------------------------------------------------------------------------- #
# 7. Concurrency: 8 locked appenders — all findings survive
# --------------------------------------------------------------------------- #
state_init "concurrent-test"
for _i in 1 2 3 4 5 6 7 8; do
    (
        finding_add "concurrent-test" "--" \
            "AP-CONC-00${_i}" "testtool" "rule${_i}" \
            "security" "warn" '[]' \
            "test${_i}.py" "${_i}" "${_i}" \
            "msg${_i}" "fix${_i}" "changed-lines" "snippet${_i}"
    ) &
done
wait

_count="$(jq 'length' "${CLAUDE_PLUGIN_DATA}/sessions/concurrent-test/findings.json")"
[ "$_count" = "8" ] \
    && ok  "concurrent: all 8 findings survived with mkdir locking" \
    || bad "concurrent: locking" "count=${_count} (expected 8)"

# --------------------------------------------------------------------------- #
# 8. Sabotage: prove the lock is load-bearing
#    Unlocked appenders with a sleep between read and write guarantee
#    all 8 readers see the initial state before any writer runs,
#    so the last mv wins and findings are lost.
# --------------------------------------------------------------------------- #
_sab_dir="${STATE_TEST_WORK}/sabotage"
mkdir -p "$_sab_dir"
printf '[]' > "${_sab_dir}/findings.json"

_append_no_lock() {
    local dir="$1" tag="$2"
    local current; current="$(cat "${dir}/findings.json" 2>/dev/null || printf '[]')"
    sleep 0.1   # widen race window: all 8 readers finish before any writer starts
    local tmp; tmp="$(mktemp "${dir}/.findings.XXXXXX")"
    printf '%s' "$current" | jq --arg t "$tag" '. + [{id:$t}]' > "$tmp"
    mv "$tmp" "${dir}/findings.json"
}

for _i in 1 2 3 4 5 6 7 8; do
    _append_no_lock "$_sab_dir" "worker-${_i}" &
done
wait

_sab_count="$(jq 'length' "${_sab_dir}/findings.json")"
if [ "$_sab_count" -lt 8 ]; then
    ok "sabotage: unlocked appenders lost findings (${_sab_count}/8 kept — lock is load-bearing)"
else
    bad "sabotage: expected <8 but got ${_sab_count}" \
        "(race not demonstrated; sleep 0.1 with 8 workers should guarantee data loss)"
fi

# --------------------------------------------------------------------------- #
# 9. state_prune: removes sessions older than 7 days, keeps fresh ones
# --------------------------------------------------------------------------- #
_old_dir="${CLAUDE_PLUGIN_DATA}/sessions/old-prune-test"
_fresh_dir="${CLAUDE_PLUGIN_DATA}/sessions/fresh-prune-test"
mkdir -p "$_old_dir" "$_fresh_dir"

# GNU touch: -d '8 days ago' sets mtime 8 days in the past.
touch -d '8 days ago' "$_old_dir" 2>/dev/null || true

state_prune

[ ! -d "$_old_dir" ] \
    && ok  "state_prune: session older than 7 days removed" \
    || bad "state_prune: old session" "still present (touch -d may not be available)"

[ -d "$_fresh_dir" ] \
    && ok  "state_prune: fresh session kept" \
    || bad "state_prune: fresh session" "removed (should not be)"
