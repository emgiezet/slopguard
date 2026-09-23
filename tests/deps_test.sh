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
    export CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    export CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=error
    deps_check_main "${DEPS_WORK}/proj-major" > /dev/null 2>&1
)
_dt_rc=$?
[ "$_dt_rc" -ne 0 ] \
    && ok  "error mode: major-behind → exit 1" \
    || bad "error mode: major-behind → exit 1" "got exit 0"

# --json must carry the same exit status: CI reads the JSON and the code.
(
    export CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    export CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=error
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
    # Read by deps_check_main inside this subshell, not exported on purpose.
    # shellcheck disable=SC2034
    export CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    # shellcheck disable=SC2034
    export CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=warn
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
# 9. Cargo (crates) parser — offline
# =========================================================================== #

mkdir -p "${DEPS_WORK}/proj-crates"
cat > "${DEPS_WORK}/proj-crates/Cargo.toml" << 'CARGO'
[package]
name = "myapp"
version = "0.1.0"

[dependencies]
serde = "1.0.100"
tokio = { version = "1.0.0", features = ["full"] }

[dev-dependencies]
test-helper = { workspace = true }
CARGO

# Unit: simple string form
_dt_cargo="$(_deps_parse_cargo "${DEPS_WORK}/proj-crates/Cargo.toml" 2>/dev/null)"
printf '%s\n' "$_dt_cargo" | grep -qF "serde|1.0.100" \
    && ok  "cargo parser: simple string dep extracted" \
    || bad "cargo parser: simple string dep extracted" "output: $_dt_cargo"

# Unit: single-line inline table form { version = "..." }
printf '%s\n' "$_dt_cargo" | grep -qF "tokio|1.0.0" \
    && ok  "cargo parser: inline-table dep extracted" \
    || bad "cargo parser: inline-table dep extracted" "output: $_dt_cargo"

# Unit: workspace dep emits a skip note on stderr
_dt_cargo_skip="$(_deps_parse_cargo "${DEPS_WORK}/proj-crates/Cargo.toml" 2>&1 >/dev/null)"
printf '%s' "$_dt_cargo_skip" | grep -q "note:" \
    && ok  "cargo parser: workspace dep skip note emitted" \
    || bad "cargo parser: workspace dep skip note emitted" "stderr: $_dt_cargo_skip"

# Integration: serde minor-behind, tokio major-behind
cat > "${DEPS_WORK}/registries-crates.json" << 'CRATESJSON'
{
  "crates": {
    "manifests": ["Cargo.toml"],
    "url": "https://crates.io/api/v1/crates/{package}",
    "latest_jq": ".crate.max_stable_version",
    "published_jq": ".crate.updated_at"
  }
}
CRATESJSON

cat > "${DEPS_WORK}/fetch-crates.sh" << 'FETCHCRATES'
#!/usr/bin/env bash
case "$1" in
    *crates.io*crates/serde)
        printf '{"crate":{"max_stable_version":"1.0.219","updated_at":"2024-01-01T00:00:00.000Z"}}'
        ;;
    *crates.io*crates/tokio)
        printf '{"crate":{"max_stable_version":"2.0.0","updated_at":"2024-01-01T00:00:00.000Z"}}'
        ;;
    *)  exit 1 ;;
esac
FETCHCRATES
chmod +x "${DEPS_WORK}/fetch-crates.sh"

_dt_crates_json="$(
    SLOPGUARD_REGISTRIES_JSON="${DEPS_WORK}/registries-crates.json"
    SLOPGUARD_FETCH_CMD="${DEPS_WORK}/fetch-crates.sh"
    export CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    export CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=warn
    deps_check_main --json "${DEPS_WORK}/proj-crates" 2>/dev/null
)"

_dt_serde_v="$(printf '%s' "$_dt_crates_json" | \
    jq -r '.[] | select(.package == "serde") | .verdict' 2>/dev/null)"
[ "$_dt_serde_v" = "minor-behind" ] \
    && ok  "crates e2e: serde 1.0.100 < 1.0.219 → minor-behind" \
    || bad "crates e2e: serde minor-behind" "got: ${_dt_serde_v}"

_dt_tokio_v="$(printf '%s' "$_dt_crates_json" | \
    jq -r '.[] | select(.package == "tokio") | .verdict' 2>/dev/null)"
[ "$_dt_tokio_v" = "major-behind" ] \
    && ok  "crates e2e: tokio 1.0.0 < 2.0.0 → major-behind" \
    || bad "crates e2e: tokio major-behind" "got: ${_dt_tokio_v}"

# =========================================================================== #
# 10. PyPI requirements.txt parser — offline
# =========================================================================== #

mkdir -p "${DEPS_WORK}/proj-pypi-req"
cat > "${DEPS_WORK}/proj-pypi-req/requirements.txt" << 'REQS'
requests==2.28.0
Flask>=2.0,<4.0
typing_extensions==4.9.0
click
# comment line
-r requirements-dev.txt
REQS

_dt_reqs="$(_deps_parse_requirements \
    "${DEPS_WORK}/proj-pypi-req/requirements.txt" 2>/dev/null)"

# Unit: exact-pinned package
printf '%s\n' "$_dt_reqs" | grep -qF "requests|==2.28.0" \
    && ok  "requirements parser: exact-pinned package extracted" \
    || bad "requirements parser: exact-pinned package extracted" "output: $_dt_reqs"

# Unit: PEP 503 lowercase normalisation (Flask → flask)
printf '%s\n' "$_dt_reqs" | grep -q "^flask|" \
    && ok  "requirements parser: name lowercased (Flask → flask)" \
    || bad "requirements parser: name lowercased" "output: $_dt_reqs"

# Unit: PEP 503 underscore normalisation (typing_extensions → typing-extensions)
printf '%s\n' "$_dt_reqs" | grep -qF "typing-extensions|==4.9.0" \
    && ok  "requirements parser: underscore normalised to dash" \
    || bad "requirements parser: underscore normalised" "output: $_dt_reqs"

# Unit: no-version package gets * sentinel
printf '%s\n' "$_dt_reqs" | grep -qF "click|*" \
    && ok  "requirements parser: no-version dep gets * sentinel" \
    || bad "requirements parser: no-version dep gets *" "output: $_dt_reqs"

# Unit: pip option (-r ...) is silently skipped
printf '%s\n' "$_dt_reqs" | grep -q "^-r\|requirements-dev" \
    && bad "requirements parser: pip option -r must be skipped" "found in output" \
    || ok  "requirements parser: pip option -r silently skipped"

# Integration: requests minor-behind (2.28.0 < 2.31.0)
cat > "${DEPS_WORK}/registries-pypi.json" << 'PYPIJSON'
{
  "pypi": {
    "manifests": ["requirements*.txt"],
    "url": "https://pypi.org/pypi/{package}/json",
    "latest_jq": ".info.version",
    "published_jq": ".urls[0].upload_time_iso_8601"
  }
}
PYPIJSON

cat > "${DEPS_WORK}/fetch-pypi.sh" << 'FETCHPYPI'
#!/usr/bin/env bash
case "$1" in
    *pypi.org*requests*)
        printf '{"info":{"version":"2.31.0"},"urls":[{"upload_time_iso_8601":"2023-05-22T00:00:00.000000Z"}]}'
        ;;
    *pypi.org*flask*)
        printf '{"info":{"version":"3.0.0"},"urls":[{"upload_time_iso_8601":"2023-09-30T00:00:00.000000Z"}]}'
        ;;
    *pypi.org*typing-extensions*)
        printf '{"info":{"version":"4.9.0"},"urls":[{"upload_time_iso_8601":"2023-12-01T00:00:00.000000Z"}]}'
        ;;
    *pypi.org*click*)
        printf '{"info":{"version":"8.1.0"},"urls":[{"upload_time_iso_8601":"2023-12-01T00:00:00.000000Z"}]}'
        ;;
    *)  exit 1 ;;
esac
FETCHPYPI
chmod +x "${DEPS_WORK}/fetch-pypi.sh"

_dt_pypi_json="$(
    SLOPGUARD_REGISTRIES_JSON="${DEPS_WORK}/registries-pypi.json"
    SLOPGUARD_FETCH_CMD="${DEPS_WORK}/fetch-pypi.sh"
    export CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    export CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=warn
    deps_check_main --json "${DEPS_WORK}/proj-pypi-req" 2>/dev/null
)"

_dt_req_v="$(printf '%s' "$_dt_pypi_json" | \
    jq -r '.[] | select(.package == "requests") | .verdict' 2>/dev/null)"
[ "$_dt_req_v" = "minor-behind" ] \
    && ok  "pypi e2e (req): requests 2.28.0 < 2.31.0 → minor-behind" \
    || bad "pypi e2e (req): requests minor-behind" "got: ${_dt_req_v}"

# click has no version (pinned=*) → unknown
_dt_click_v="$(printf '%s' "$_dt_pypi_json" | \
    jq -r '.[] | select(.package == "click") | .verdict' 2>/dev/null)"
[ "$_dt_click_v" = "unknown" ] \
    && ok  "pypi e2e (req): click no-version → unknown" \
    || bad "pypi e2e (req): click no-version → unknown" "got: ${_dt_click_v}"

# =========================================================================== #
# 11. PyPI pyproject.toml parser — offline
# =========================================================================== #

mkdir -p "${DEPS_WORK}/proj-pypi-toml"
cat > "${DEPS_WORK}/proj-pypi-toml/pyproject.toml" << 'PYPROJ'
[project]
name = "myapp"
version = "0.1.0"
dependencies = [
    "requests>=2.28.0",
    "Click==8.1.0",
]

[tool.poetry.dependencies]
python = "^3.9"
django = "^4.2.0"
requests-oauthlib = { version = "^1.3.0", extras = ["rsa"] }
PYPROJ

_dt_pep621="$(_deps_parse_pyproject \
    "${DEPS_WORK}/proj-pypi-toml/pyproject.toml" 2>/dev/null)"

# Unit: PEP 621 dep extracted
printf '%s\n' "$_dt_pep621" | grep -qF "requests|>=2.28.0" \
    && ok  "pyproject parser (PEP 621): requests extracted" \
    || bad "pyproject parser (PEP 621): requests extracted" "output: $_dt_pep621"

# Unit: PEP 621 name lowercased (Click → click)
printf '%s\n' "$_dt_pep621" | grep -q "^click|" \
    && ok  "pyproject parser (PEP 621): Click lowercased to click" \
    || bad "pyproject parser (PEP 621): Click lowercased" "output: $_dt_pep621"

# Unit: Poetry dep extracted; python key is skipped
printf '%s\n' "$_dt_pep621" | grep -q "^django|" \
    && ok  "pyproject parser (Poetry): django extracted" \
    || bad "pyproject parser (Poetry): django extracted" "output: $_dt_pep621"

printf '%s\n' "$_dt_pep621" | grep -q "^python|" \
    && bad "pyproject parser (Poetry): python constraint must be skipped" "found in output" \
    || ok  "pyproject parser (Poetry): python constraint skipped"

# Unit: Poetry inline-table dep with extras (requests-oauthlib)
printf '%s\n' "$_dt_pep621" | grep -q "^requests-oauthlib|" \
    && ok  "pyproject parser (Poetry): inline-table dep with extras extracted" \
    || bad "pyproject parser (Poetry): inline-table dep with extras" "output: $_dt_pep621"

# Integration: click ok (8.1.0 == 8.1.0), django major-behind (^4.2.0 < 5.0.0)
cat > "${DEPS_WORK}/registries-pypi-toml.json" << 'PYPITOMLJSON'
{
  "pypi": {
    "manifests": ["pyproject.toml"],
    "url": "https://pypi.org/pypi/{package}/json",
    "latest_jq": ".info.version",
    "published_jq": ".urls[0].upload_time_iso_8601"
  }
}
PYPITOMLJSON

cat > "${DEPS_WORK}/fetch-pypi-toml.sh" << 'FETCHPYPITOML'
#!/usr/bin/env bash
case "$1" in
    *pypi.org*requests-oauthlib*)
        printf '{"info":{"version":"1.3.1"},"urls":[{"upload_time_iso_8601":"2023-01-01T00:00:00.000000Z"}]}'
        ;;
    *pypi.org*requests*)
        printf '{"info":{"version":"2.31.0"},"urls":[{"upload_time_iso_8601":"2023-05-22T00:00:00.000000Z"}]}'
        ;;
    *pypi.org*click*)
        printf '{"info":{"version":"8.1.0"},"urls":[{"upload_time_iso_8601":"2023-12-01T00:00:00.000000Z"}]}'
        ;;
    *pypi.org*django*)
        printf '{"info":{"version":"5.0.0"},"urls":[{"upload_time_iso_8601":"2023-12-01T00:00:00.000000Z"}]}'
        ;;
    *)  exit 1 ;;
esac
FETCHPYPITOML
chmod +x "${DEPS_WORK}/fetch-pypi-toml.sh"

_dt_toml_json="$(
    SLOPGUARD_REGISTRIES_JSON="${DEPS_WORK}/registries-pypi-toml.json"
    SLOPGUARD_FETCH_CMD="${DEPS_WORK}/fetch-pypi-toml.sh"
    export CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    export CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=warn
    deps_check_main --json "${DEPS_WORK}/proj-pypi-toml" 2>/dev/null
)"

_dt_click_toml_v="$(printf '%s' "$_dt_toml_json" | \
    jq -r '.[] | select(.package == "click") | .verdict' 2>/dev/null)"
[ "$_dt_click_toml_v" = "ok" ] \
    && ok  "pypi e2e (toml): click 8.1.0 == 8.1.0 → ok" \
    || bad "pypi e2e (toml): click ok" "got: ${_dt_click_toml_v}"

_dt_django_v="$(printf '%s' "$_dt_toml_json" | \
    jq -r '.[] | select(.package == "django") | .verdict' 2>/dev/null)"
[ "$_dt_django_v" = "major-behind" ] \
    && ok  "pypi e2e (toml): django 4.2.0 < 5.0.0 → major-behind" \
    || bad "pypi e2e (toml): django major-behind" "got: ${_dt_django_v}"

# =========================================================================== #
# 12. Maven pom.xml parser — offline
# =========================================================================== #

mkdir -p "${DEPS_WORK}/proj-maven"
cat > "${DEPS_WORK}/proj-maven/pom.xml" << 'POM'
<project>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
      <version>3.1.0</version>
    </dependency>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>${junit.version}</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>mylib</artifactId>
      <version>2.0.0</version>
    </dependency>
  </dependencies>
</project>
POM

_dt_pom="$(_deps_parse_pom "${DEPS_WORK}/proj-maven/pom.xml" 2>/dev/null)"

# Unit: groupId:artifactId composite key
printf '%s\n' "$_dt_pom" | grep -qF "g:org.springframework.boot+AND+a:spring-boot-starter|3.1.0" \
    && ok  "pom parser: groupId+artifactId composite key extracted" \
    || bad "pom parser: composite key extracted" "output: $_dt_pom"

# Unit: second non-property dep extracted
printf '%s\n' "$_dt_pom" | grep -qF "g:com.example+AND+a:mylib|2.0.0" \
    && ok  "pom parser: second dep extracted" \
    || bad "pom parser: second dep extracted" "output: $_dt_pom"

# Unit: property-ref version is counted and noted on stderr (not in stdout)
printf '%s\n' "$_dt_pom" | grep -q "junit" \
    && bad "pom parser: property-ref dep must not appear in stdout" "found in output" \
    || ok  "pom parser: property-ref version not in stdout"

_dt_pom_skip="$(_deps_parse_pom "${DEPS_WORK}/proj-maven/pom.xml" 2>&1 >/dev/null)"
printf '%s' "$_dt_pom_skip" | grep -q "note:" \
    && ok  "pom parser: property-ref skip note emitted to stderr" \
    || bad "pom parser: skip note emitted" "stderr: $_dt_pom_skip"

# Integration: spring-boot-starter minor-behind (3.1.0 < 3.2.0), mylib ok (2.0.0 == 2.0.0)
cat > "${DEPS_WORK}/registries-maven.json" << 'MAVENJSON'
{
  "maven": {
    "manifests": ["pom.xml"],
    "url": "https://search.maven.org/solrsearch/select?q={package}&rows=1&wt=json",
    "latest_jq": ".response.docs[0].latestVersion",
    "published_jq": ".response.docs[0].timestamp / 1000 | todate"
  }
}
MAVENJSON

cat > "${DEPS_WORK}/fetch-maven.sh" << 'FETCHMAVEN'
#!/usr/bin/env bash
case "$1" in
    *spring-boot-starter*)
        printf '{"response":{"docs":[{"latestVersion":"3.2.0","timestamp":1703174400000}]}}'
        ;;
    *mylib*)
        printf '{"response":{"docs":[{"latestVersion":"2.0.0","timestamp":1700000000000}]}}'
        ;;
    *)  exit 1 ;;
esac
FETCHMAVEN
chmod +x "${DEPS_WORK}/fetch-maven.sh"

_dt_maven_json="$(
    SLOPGUARD_REGISTRIES_JSON="${DEPS_WORK}/registries-maven.json"
    SLOPGUARD_FETCH_CMD="${DEPS_WORK}/fetch-maven.sh"
    export CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true
    export CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS=warn
    deps_check_main --json "${DEPS_WORK}/proj-maven" 2>/dev/null
)"

_dt_sbs_v="$(printf '%s' "$_dt_maven_json" | \
    jq -r '.[] | select(.package | contains("spring-boot-starter")) | .verdict' 2>/dev/null)"
[ "$_dt_sbs_v" = "minor-behind" ] \
    && ok  "maven e2e: spring-boot-starter 3.1.0 < 3.2.0 → minor-behind" \
    || bad "maven e2e: spring-boot-starter minor-behind" "got: ${_dt_sbs_v}"

_dt_mylib_v="$(printf '%s' "$_dt_maven_json" | \
    jq -r '.[] | select(.package | contains("mylib")) | .verdict' 2>/dev/null)"
[ "$_dt_mylib_v" = "ok" ] \
    && ok  "maven e2e: mylib 2.0.0 == 2.0.0 → ok" \
    || bad "maven e2e: mylib ok" "got: ${_dt_mylib_v}"

# =========================================================================== #
# Standalone summary
# =========================================================================== #

if [ "${_dt_standalone:-0}" = "1" ]; then
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ] || exit 1
fi
