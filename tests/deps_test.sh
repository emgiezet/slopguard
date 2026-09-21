#!/usr/bin/env bash
# deps_test.sh — tests for lib/deps.sh.
#
# Runs fully offline: SLOPGUARD_FETCH_CMD points to a fixture script;
# SLOPGUARD_REGISTRIES_JSON points to a fixture registries file.
#
# Sourced by tests/run-tests (ok()/bad() pre-defined there).
# Also runnable standalone:  bash tests/deps_test.sh
set -uo pipefail

# ── Bootstrap when run standalone ────────────────────────────────────────── #
if [ -z "${PLUGIN_ROOT:-}" ]; then
    _dt_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    PLUGIN_ROOT="$(cd "${_dt_dir}/.." && pwd)"
    : "${CLAUDE_PLUGIN_ROOT:=$PLUGIN_ROOT}"
fi

if ! declare -f ok >/dev/null 2>&1; then
    PASS=0; FAIL=0
    ok()  { printf '  ok    %s\n' "$1"; PASS=$(( PASS + 1 )); }
    bad() { printf '  FAIL  %s: %s\n' "$1" "$2"; FAIL=$(( FAIL + 1 )); }
    _dt_standalone=1
    printf 'deps_test.sh\n\n'
fi

# shellcheck source=../lib/deps.sh
. "${PLUGIN_ROOT}/lib/deps.sh"

# ── Temp dir — cleaned up at exit ────────────────────────────────────────── #
DEPS_WORK="${TMPDIR:-/tmp}/slopguard-deps-test-$$"
mkdir -p "$DEPS_WORK"
trap 'rm -rf "$DEPS_WORK"' EXIT INT TERM

# =========================================================================== #
# 1. deps_version_cmp
# =========================================================================== #

_vc() {
    local got; got="$(deps_version_cmp "$1" "$2")"
    [ "$got" = "$3" ] \
        && ok  "version_cmp: $1 vs $2 → $3" \
        || bad "version_cmp: $1 vs $2 → $3" "got: $got"
}

_vc "1.2.3"    "1.2.3"    "0"   # equal
_vc "1.2.0"    "1.2.3"    "-1"  # patch behind
_vc "2.0.0"    "1.9.9"    "1"   # ahead
_vc "v1.2.3"   "1.2.3"    "0"   # strip v prefix
_vc "^1.2.3"   "1.2.3"    "0"   # strip ^ prefix
_vc "1.2"      "1.2.0"    "0"   # different component count — equal
_vc "1.0.0-rc1" "1.0.0"   "-1"  # prerelease sorts below release
_vc "1.0.0"    "1.0.0-beta.2" "1"  # release is above prerelease

# =========================================================================== #
# 2. deps_age_days
# =========================================================================== #

# A date well in the past — result must be a non-negative integer > 1000.
_age_past="$(deps_age_days "2020-01-01T00:00:00.000Z")"
if [[ "$_age_past" =~ ^[0-9]+$ ]] && [ "$_age_past" -gt 1000 ]; then
    ok  "deps_age_days: 2020-01-01 returns > 1000 days"
else
    bad "deps_age_days: 2020-01-01 returns > 1000 days" "got: ${_age_past}"
fi

# Garbage input must return -1.
_age_bad="$(deps_age_days "not-a-date")"
[ "$_age_bad" = "-1" ] \
    && ok  "deps_age_days: invalid input → -1" \
    || bad "deps_age_days: invalid input → -1" "got: ${_age_bad}"

# =========================================================================== #
# 3. deps_verdict
# =========================================================================== #

_vt() {
    local got; got="$(deps_verdict "$1" "$2" "$3" "$4")"
    [ "$got" = "$5" ] \
        && ok  "verdict: $1 vs $2 (age=$3, cool=$4) → $5" \
        || bad "verdict: $1 vs $2 (age=$3, cool=$4) → $5" "got: $got"
}

_vt "18.3.1" "18.3.1" "100" "3" "ok"           # equal → ok
_vt "18.2.0" "18.3.1" "100" "3" "minor-behind"  # same major, lower minor
_vt "0.21.1" "1.7.2"  "400" "3" "major-behind"  # major 0 vs 1
_vt "0.21.1" "1.7.2"  "1"   "3" "too-fresh"     # too-fresh outranks major-behind
_vt "2.0.0"  "2.0.0"  "0"   "3" "too-fresh"     # age=0 < cooldown=3, even though ok
_vt "*"      "1.0.0"  "100" "3" "unknown"        # junk pinned version
_vt "1.0.0"  "@latest" "100" "3" "unknown"       # junk latest version

# =========================================================================== #
# Fixture setup
# =========================================================================== #

# Registries fixture — npm only (sufficient to exercise all code paths).
cat > "${DEPS_WORK}/registries.json" << 'JSON'
{
  "npm": {
    "manifests": ["package.json"],
    "url": "https://registry.npmjs.org/{package}",
    "latest_jq": ".\"dist-tags\".latest",
    "published_jq": ".time[$v]"
  }
}
JSON

# Fetch fixture — responds to known package URLs; never touches the real network.
# "fresh-pkg" returns a publication timestamp 1 day ago so it is within the
# 3-day cooldown window.
cat > "${DEPS_WORK}/fetch.sh" << 'FETCH'
#!/usr/bin/env bash
case "$1" in
    *npmjs.org/react)
        printf '{"dist-tags":{"latest":"18.3.1"},"time":{"18.3.1":"2024-04-26T00:00:00.000Z"}}'
        ;;
    *npmjs.org/axios)
        # 0.21.1 installed vs 1.7.2 latest → major-behind; old enough (> 3 days)
        printf '{"dist-tags":{"latest":"1.7.2"},"time":{"1.7.2":"2024-06-12T00:00:00.000Z"}}'
        ;;
    *npmjs.org/fresh-pkg)
        # Published 1 day ago — within the 3-day cooldown window → too-fresh
        _ts="$(date -d '1 day ago' '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null \
            || date -j -v-1d '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null \
            || printf '2026-09-20T00:00:00.000Z')"
        printf '{"dist-tags":{"latest":"2.0.0"},"time":{"2.0.0":"%s"}}' "$_ts"
        ;;
    *npmjs.org/fail-pkg)
        # Simulated fetch failure
        exit 1
        ;;
    *npmjs.org/lodash)
        printf '{"dist-tags":{"latest":"4.17.21"},"time":{"4.17.21":"2021-02-20T00:00:00.000Z"}}'
        ;;
    *)
        exit 1
        ;;
esac
FETCH
chmod +x "${DEPS_WORK}/fetch.sh"

# Fixture project with npm package.json.
# react:     18.3.1 (pinned == latest)           → ok
# axios:     0.21.1 (latest 1.7.2, age > 3 days) → major-behind
# fresh-pkg: 1.9.9  (latest 2.0.0, age 1 day)    → too-fresh
# fail-pkg:  1.0.0  (fetch fails)                 → unknown
# lodash:    4.17.21 in devDependencies           → ok
mkdir -p "${DEPS_WORK}/project"
cat > "${DEPS_WORK}/project/package.json" << 'PKG'
{
  "dependencies": {
    "react":     "18.3.1",
    "axios":     "0.21.1",
    "fresh-pkg": "1.9.9",
    "fail-pkg":  "1.0.0"
  },
  "devDependencies": {
    "lodash": "4.17.21"
  }
}
PKG

# Minimal project with only one major-behind dependency (for exit-code tests).
mkdir -p "${DEPS_WORK}/proj-major"
cat > "${DEPS_WORK}/proj-major/package.json" << 'PKG2'
{ "dependencies": { "axios": "0.21.1" } }
PKG2

# Export globals so all subshells see them.
export SLOPGUARD_REGISTRIES_JSON="${DEPS_WORK}/registries.json"
export SLOPGUARD_FETCH_CMD="${DEPS_WORK}/fetch.sh"
export CLAUDE_PLUGIN_OPTION_DEPENDENCY_COOLDOWN_DAYS="3"

# =========================================================================== #
# 4. Network gate — no fetch attempted, exit 0
# =========================================================================== #

# Sentinel-creating fetch: if called, it creates a file we can detect.
_dt_sentinel="${DEPS_WORK}/fetch-sentinel-$$"
printf '#!/usr/bin/env bash\ntouch %s\nexit 1\n' "$_dt_sentinel" \
    > "${DEPS_WORK}/sentinel-fetch.sh"
chmod +x "${DEPS_WORK}/sentinel-fetch.sh"

(
    unset CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK 2>/dev/null || true
    SLOPGUARD_FETCH_CMD="${DEPS_WORK}/sentinel-fetch.sh"
    deps_check_main "${DEPS_WORK}/project" > /dev/null 2>&1
)
[ ! -f "$_dt_sentinel" ] \
    && ok  "network gate: no fetch when ALLOW_NETWORK unset" \
    || bad "network gate: no fetch when ALLOW_NETWORK unset" "fetch was invoked"

# Exit code must be 0 even though there are no results.
(
    unset CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK 2>/dev/null || true
    SLOPGUARD_FETCH_CMD="${DEPS_WORK}/sentinel-fetch.sh"
    deps_check_main "${DEPS_WORK}/project" > /dev/null 2>&1
)
_dt_rc=$?
[ "$_dt_rc" -eq 0 ] \
    && ok  "network gate: exits 0 when network disabled" \
    || bad "network gate: exits 0 when network disabled" "got exit $_dt_rc"

# =========================================================================== #
# 5. dependency_freshness=error — major-behind → exit 1
# =========================================================================== #

(
    CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=error
    deps_check_main "${DEPS_WORK}/proj-major" > /dev/null 2>&1
)
_dt_rc=$?
[ "$_dt_rc" -ne 0 ] \
    && ok  "error mode: major-behind → exit 1" \
    || bad "error mode: major-behind → exit 1" "got exit 0"

# --json must carry the same exit status: CI reads the JSON and the code.
(
    CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=error
    deps_check_main --json "${DEPS_WORK}/proj-major" > /dev/null 2>&1
)
_dt_rc=$?
[ "$_dt_rc" -ne 0 ] \
    && ok  "error mode: --json → exit 1" \
    || bad "error mode: --json → exit 1" "got exit 0"

# =========================================================================== #
# 6. dependency_freshness=warn — major-behind → exit 0
# =========================================================================== #

(
    CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=warn
    deps_check_main "${DEPS_WORK}/proj-major" > /dev/null 2>&1
)
_dt_rc=$?
[ "$_dt_rc" -eq 0 ] \
    && ok  "warn mode: major-behind → exit 0" \
    || bad "warn mode: major-behind → exit 0" "got exit $_dt_rc"

# =========================================================================== #
# 7. --json output
# =========================================================================== #

_dt_json="$(
    CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true \
    CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=warn \
    deps_check_main --json "${DEPS_WORK}/project" 2>/dev/null
)"

# Must be a valid JSON array.
_dt_len="$(printf '%s' "$_dt_json" | jq 'length' 2>/dev/null)" || _dt_len=""
[[ "$_dt_len" =~ ^[0-9]+$ ]] && [ "$_dt_len" -gt 0 ] \
    && ok  "json: valid JSON array with ${_dt_len} entries" \
    || bad "json: valid JSON array" "jq parse failed or empty; len=${_dt_len:-err}"

# Every entry must carry the six required fields.
_dt_bad_fields="$(printf '%s' "$_dt_json" | jq '
    [.[] | select(
        (.ecosystem | not) or (.package | not) or (.pinned | not) or
        (.latest     | not) or (.verdict | not) or (.age_days == null)
    )] | length
' 2>/dev/null)" || _dt_bad_fields="err"
[ "${_dt_bad_fields:-err}" = "0" ] \
    && ok  "json: all entries have the six required fields" \
    || bad "json: all entries have the six required fields" "missing-field count=${_dt_bad_fields}"

# react (pinned == latest) must be ok.
_dt_react_v="$(printf '%s' "$_dt_json" | \
    jq -r '.[] | select(.package == "react") | .verdict' 2>/dev/null)"
[ "$_dt_react_v" = "ok" ] \
    && ok  "json: react verdict is ok" \
    || bad "json: react verdict is ok" "got: ${_dt_react_v}"

# axios must be major-behind (major 0 vs 1, published long ago).
_dt_axios_v="$(printf '%s' "$_dt_json" | \
    jq -r '.[] | select(.package == "axios") | .verdict' 2>/dev/null)"
[ "$_dt_axios_v" = "major-behind" ] \
    && ok  "json: axios verdict is major-behind" \
    || bad "json: axios verdict is major-behind" "got: ${_dt_axios_v}"

# fresh-pkg must be too-fresh (latest published 1 day ago < 3-day cooldown).
_dt_fresh_v="$(printf '%s' "$_dt_json" | \
    jq -r '.[] | select(.package == "fresh-pkg") | .verdict' 2>/dev/null)"
[ "$_dt_fresh_v" = "too-fresh" ] \
    && ok  "json: fresh-pkg verdict is too-fresh" \
    || bad "json: fresh-pkg verdict is too-fresh" "got: ${_dt_fresh_v}"

# =========================================================================== #
# 8. Fetch failure → unknown verdict; run does not abort
# =========================================================================== #

# fail-pkg's fetch returns exit 1; verdict must be unknown.
_dt_fail_v="$(printf '%s' "$_dt_json" | \
    jq -r '.[] | select(.package == "fail-pkg") | .verdict' 2>/dev/null)"
[ "$_dt_fail_v" = "unknown" ] \
    && ok  "fetch failure: fail-pkg gets unknown verdict" \
    || bad "fetch failure: fail-pkg gets unknown verdict" "got: ${_dt_fail_v}"

# Other packages after fail-pkg must still appear (run continued).
_dt_ok_count="$(printf '%s' "$_dt_json" | \
    jq '[.[] | select(.verdict == "ok")] | length' 2>/dev/null)" || _dt_ok_count=0
[ "${_dt_ok_count:-0}" -ge 1 ] \
    && ok  "fetch failure: run continues; ${_dt_ok_count} ok package(s) processed" \
    || bad "fetch failure: run continues after failure" "ok_count=${_dt_ok_count}"

# =========================================================================== #
# Standalone summary
# =========================================================================== #

if [ "${_dt_standalone:-0}" = "1" ]; then
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ] || exit 1
fi
