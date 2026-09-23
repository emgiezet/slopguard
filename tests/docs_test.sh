#!/usr/bin/env bash
# docs_test.sh — tests for lib/docs.sh.
#
# Sourced by tests/run-tests; ok() and bad() are pre-defined there.
# When run directly, defines its own ok/bad stubs and prints a summary.

if [ -z "${PASS+x}" ]; then
    PASS=0; FAIL=0
    ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
    bad() { printf '  FAIL  %s: %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
    TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
    : "${CLAUDE_PLUGIN_ROOT:=$PLUGIN_ROOT}"
    _DOCS_STANDALONE=1
fi

DOCS_TEST_WORK="${TMPDIR:-/tmp}/slop-guard-docs-test-$$"
export CLAUDE_PLUGIN_DATA="${DOCS_TEST_WORK}/data"
mkdir -p "${CLAUDE_PLUGIN_DATA}/sessions"
trap 'rm -rf "${DOCS_TEST_WORK}"' EXIT INT TERM

# shellcheck source=../lib/state.sh
. "${PLUGIN_ROOT}/lib/state.sh"
# shellcheck source=../lib/docs.sh
. "${PLUGIN_ROOT}/lib/docs.sh"

SID="docs-test-sess"
AID="docs-test-agent"

# --------------------------------------------------------------------------- #
# 1. A noted library is seen
# --------------------------------------------------------------------------- #
docs_note "$SID" "$AID" "laravel"
docs_seen "$SID" "$AID" "laravel" \
    && ok  "docs_seen: noted library is seen" \
    || bad "docs_seen: noted library is seen" "returned non-zero"

# --------------------------------------------------------------------------- #
# 2. An unrelated library is not seen
# --------------------------------------------------------------------------- #
docs_seen "$SID" "$AID" "django" \
    && bad "docs_seen: unrelated library" "returned zero (false match)" \
    || ok  "docs_seen: unrelated library is not seen"

# --------------------------------------------------------------------------- #
# 3. Substring matching — needle contained in recorded value
# --------------------------------------------------------------------------- #
# '/laravel/laravel' contains 'laravel'
docs_seen "$SID" "$AID" "/laravel/laravel" \
    && ok  "docs_seen: needle in hay (/laravel/laravel vs laravel)" \
    || bad "docs_seen: needle in hay" "no match found"

# --------------------------------------------------------------------------- #
# 4. Substring matching — recorded value contained in needle
# --------------------------------------------------------------------------- #
SID2="docs-test-sess-2"
docs_note "$SID2" "$AID" "/laravel/laravel"
docs_seen "$SID2" "$AID" "laravel" \
    && ok  "docs_seen: hay in needle (laravel vs /laravel/laravel)" \
    || bad "docs_seen: hay in needle" "no match found"

# --------------------------------------------------------------------------- #
# 5. Case-insensitive matching
# --------------------------------------------------------------------------- #
SID3="docs-test-sess-3"
docs_note "$SID3" "$AID" "React"
docs_seen "$SID3" "$AID" "react" \
    && ok  "docs_seen: case-insensitive (React vs react)" \
    || bad "docs_seen: case-insensitive" "no match found"
docs_seen "$SID3" "$AID" "REACT" \
    && ok  "docs_seen: case-insensitive (React vs REACT)" \
    || bad "docs_seen: case-insensitive REACT" "no match found"

# --------------------------------------------------------------------------- #
# 6. A second note of the same library does not duplicate the entry
# --------------------------------------------------------------------------- #
docs_note "$SID" "$AID" "laravel"
docs_note "$SID" "$AID" "laravel"
_dl="${CLAUDE_PLUGIN_DATA}/sessions/${SID}/${AID}/docs-lookups.json"
_count="$(jq 'length' "$_dl")"
[ "$_count" = "1" ] \
    && ok  "docs_note: no duplicate on repeated note" \
    || bad "docs_note: no duplicate on repeated note" "count=${_count}"

# --------------------------------------------------------------------------- #
# 7. A corrupt docs-lookups.json degrades to [] instead of failing
# --------------------------------------------------------------------------- #
SID4="docs-test-sess-corrupt"
state_init "$SID4" "agent-x"
_cf="${CLAUDE_PLUGIN_DATA}/sessions/${SID4}/agent-x/docs-lookups.json"
printf 'NOT JSON!!!\n' > "$_cf"
docs_note "$SID4" "agent-x" "symfony"
_rc=$?
[ "$_rc" -eq 0 ] \
    && ok  "docs_note: corrupt file does not fail docs_note" \
    || bad "docs_note: corrupt file does not fail" "rc=${_rc}"
docs_seen "$SID4" "agent-x" "symfony" \
    && ok  "docs_seen: entry recovered after corrupt file" \
    || bad "docs_seen: entry recovered after corrupt file" "not seen"

# --------------------------------------------------------------------------- #
# 8. docs_remember / docs_recall — hit for same major.minor
# --------------------------------------------------------------------------- #
docs_remember "laravel" "10.3.5"
docs_recall   "laravel" "10.3.5" \
    && ok  "docs_recall: hit for same major.minor (10.3)" \
    || bad "docs_recall: hit for same major.minor" "not found"

# Same major.minor, different patch — must still hit
docs_recall   "laravel" "10.3.99" \
    && ok  "docs_recall: hit for same major.minor different patch (10.3)" \
    || bad "docs_recall: hit for same major.minor different patch" "not found"

# --------------------------------------------------------------------------- #
# 9. docs_recall — miss after a minor bump
# --------------------------------------------------------------------------- #
docs_recall "laravel" "10.4.0" \
    && bad "docs_recall: minor bump should miss" "returned 0 (false hit)" \
    || ok  "docs_recall: miss after minor bump (10.3 → 10.4)"

# Major bump must also miss
docs_recall "laravel" "11.0.0" \
    && bad "docs_recall: major bump should miss" "returned 0 (false hit)" \
    || ok  "docs_recall: miss after major bump (10.3 → 11.0)"

# --------------------------------------------------------------------------- #
# 10. Library string containing '/' produces a valid filename
# --------------------------------------------------------------------------- #
docs_remember "/laravel/laravel" "10.3.0"
_key="$(_docs_key "/laravel/laravel" "10.3.0")"
_mem_file="${CLAUDE_PLUGIN_DATA}/docs-seen/${_key}"
[ -f "$_mem_file" ] \
    && ok  "docs_remember: '/' in library produces valid filename (${_key})" \
    || bad "docs_remember: '/' in library produces valid filename" "file missing: ${_mem_file}"

# Verify filename contains no forward slash (making it a valid single component)
case "$_key" in
    */*) bad  "docs_key: key must not contain /" "got: ${_key}" ;;
    *)   ok   "docs_key: sanitised key has no /" ;;
esac

# --------------------------------------------------------------------------- #
# 11. End-to-end: slopguard note-docs with a realistic PreToolUse payload
# --------------------------------------------------------------------------- #
_E2E_SID="docs-e2e-sess"
_E2E_AID="agent-main"
_E2E_PAYLOAD="$(jq -n \
    --arg session_id "$_E2E_SID" \
    --arg agent_id   "$_E2E_AID" \
    '{
        session_id: $session_id,
        agent_id:   $agent_id,
        hook_event_name: "PreToolUse",
        tool_name: "mcp__context7__get-library-docs",
        tool_input: {
            context7CompatibleLibraryID: "/laravel/laravel",
            topic: "routing",
            tokens: 5000
        }
    }')"

_e2e_stdout="$(printf '%s' "$_E2E_PAYLOAD" \
    | CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" \
      CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
      "${PLUGIN_ROOT}/bin/slopguard" note-docs)"
_e2e_rc=$?

[ "$_e2e_rc" -eq 0 ] \
    && ok  "slopguard note-docs: exits 0" \
    || bad "slopguard note-docs: exits 0" "rc=${_e2e_rc}"

[ -z "$_e2e_stdout" ] \
    && ok  "slopguard note-docs: no stdout" \
    || bad "slopguard note-docs: no stdout" "got: ${_e2e_stdout}"

_e2e_dl="${CLAUDE_PLUGIN_DATA}/sessions/${_E2E_SID}/${_E2E_AID}/docs-lookups.json"
[ -f "$_e2e_dl" ] \
    && ok  "slopguard note-docs: docs-lookups.json created" \
    || bad "slopguard note-docs: docs-lookups.json created" "file missing: ${_e2e_dl}"

if [ -f "$_e2e_dl" ]; then
    _e2e_lib="$(jq -r '.[0].library' "$_e2e_dl")"
    [ "$_e2e_lib" = "/laravel/laravel" ] \
        && ok  "slopguard note-docs: library recorded correctly" \
        || bad "slopguard note-docs: library recorded" "got: ${_e2e_lib}"

    _e2e_count="$(jq 'length' "$_e2e_dl")"
    [ "$_e2e_count" = "1" ] \
        && ok  "slopguard note-docs: exactly one entry in docs-lookups.json" \
        || bad "slopguard note-docs: entry count" "got: ${_e2e_count}"

    printf 'docs-lookups.json content after note-docs:\n'
    jq '.' "$_e2e_dl"
fi

# --------------------------------------------------------------------------- #
# 12. note-docs → docs_remember wiring: end-to-end via slopguard binary
# --------------------------------------------------------------------------- #
_MEM_STACKS="${DOCS_TEST_WORK}/mem-stacks.json"
printf '{"laravel":{"tier":1,"globs":["**/*.php"],"context7":"laravel"}}\n' \
    > "$_MEM_STACKS"

_MEM_SID="docs-mem-sess"
_MEM_AID="agent-mem"
_MEM_SDIR="${CLAUDE_PLUGIN_DATA}/sessions/${_MEM_SID}/${_MEM_AID}"
mkdir -p "${_MEM_SDIR}"
printf '{"framework_versions":{"laravel":"v12.4.1"}}\n' > "${_MEM_SDIR}/profile.json"

# Run note-docs with a library that matches laravel's context7 query.
printf '%s' "$(jq -n \
    --arg session_id "$_MEM_SID" \
    --arg agent_id   "$_MEM_AID" \
    '{session_id:$session_id,agent_id:$agent_id,
      hook_event_name:"PreToolUse",tool_name:"mcp__context7__get-library-docs",
      tool_input:{context7CompatibleLibraryID:"/laravel/laravel",topic:"routing",tokens:5000}}')" \
    | CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" \
      CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
      SLOPGUARD_STACKS_JSON="$_MEM_STACKS" \
      "${PLUGIN_ROOT}/bin/slopguard" note-docs

_MEM_KEY="$(_docs_key "laravel" "v12.4.1")"
_MEM_FILE="${CLAUDE_PLUGIN_DATA}/docs-seen/${_MEM_KEY}"
[ -f "$_MEM_FILE" ] \
    && ok  "note-docs→docs_remember: memory file created (${_MEM_KEY})" \
    || bad "note-docs→docs_remember: memory file created" "missing: ${_MEM_FILE}"

docs_recall "laravel" "v12.4.1" \
    && ok  "note-docs→docs_recall: hit for same major.minor after note-docs" \
    || bad "note-docs→docs_recall: hit" "file not found: ${_MEM_FILE}"

# An unrelated library must not create a memory file.
_UNREL_SID="docs-mem-unrel"
_UNREL_SDIR="${CLAUDE_PLUGIN_DATA}/sessions/${_UNREL_SID}/${_MEM_AID}"
mkdir -p "${_UNREL_SDIR}"
printf '{"framework_versions":{"laravel":"v12.4.1"}}\n' > "${_UNREL_SDIR}/profile.json"

printf '%s' "$(jq -n \
    --arg session_id "$_UNREL_SID" \
    --arg agent_id   "$_MEM_AID" \
    '{session_id:$session_id,agent_id:$agent_id,
      hook_event_name:"PreToolUse",tool_name:"mcp__context7__get-library-docs",
      tool_input:{context7CompatibleLibraryID:"django",topic:"orm",tokens:5000}}')" \
    | CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" \
      CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
      SLOPGUARD_STACKS_JSON="$_MEM_STACKS" \
      "${PLUGIN_ROOT}/bin/slopguard" note-docs

_UNREL_KEY="$(_docs_key "django" "v12.4.1")"
_UNREL_FILE="${CLAUDE_PLUGIN_DATA}/docs-seen/${_UNREL_KEY}"
[ ! -f "$_UNREL_FILE" ] \
    && ok  "note-docs→docs_remember: unrelated library (django) writes no memory file" \
    || bad "note-docs→docs_remember: unrelated library must not write memory" "found: ${_UNREL_FILE}"

# Minor bump must miss.
docs_recall "laravel" "v12.5.0" \
    && bad "note-docs→docs_recall: minor bump should miss" "returned 0 (false hit)" \
    || ok  "note-docs→docs_recall: miss after minor bump (v12.4 → v12.5)"

# --------------------------------------------------------------------------- #
# Standalone summary
# --------------------------------------------------------------------------- #
if [ "${_DOCS_STANDALONE:-0}" = "1" ]; then
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ] || exit 1
fi
