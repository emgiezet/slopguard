#!/usr/bin/env bash
# read_test.sh — standalone tests for the pre-read hook policy.
#
# Run directly: tests/read_test.sh
# Each case pipes a hook-contract JSON fixture through hooks/pre-read and
# asserts the resulting permissionDecision (deny / ask / allow).
#
# "allow" is represented by exit 0 with empty stdout — the hook emits no JSON
# when it permits the read.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
: "${CLAUDE_PLUGIN_ROOT:=$PLUGIN_ROOT}"

HOOK="${PLUGIN_ROOT}/hooks/pre-read"
CONTRACT="${TESTS_DIR}/hook-contract"

[ -x "$HOOK" ] || { printf 'FATAL: %s is not executable\n' "$HOOK" >&2; exit 1; }

PASS=0
FAIL=0

ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s: %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

printf 'pre-read hook tests\n\n'

# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

# run_hook <fixture-path>
# Pipes the fixture to the hook. Sets HOOK_EXIT and HOOK_OUTPUT.
run_hook() {
    HOOK_OUTPUT="$("$HOOK" < "$1" 2>/dev/null)"
    HOOK_EXIT=$?
}

# decision from the last run_hook output (empty = allow)
last_decision() {
    if [ -z "$HOOK_OUTPUT" ]; then
        printf 'allow'
    else
        printf '%s' "$HOOK_OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
    fi
}

assert_deny() {
    local label="$1" fixture="$2"
    run_hook "$fixture"
    local got; got="$(last_decision)"
    [ "$got" = "deny" ] \
        && ok  "deny: $label" \
        || bad "deny: $label" "expected deny, got '${got}' (exit=${HOOK_EXIT})"
}

assert_ask() {
    local label="$1" fixture="$2"
    run_hook "$fixture"
    local got; got="$(last_decision)"
    [ "$got" = "ask" ] \
        && ok  "ask: $label" \
        || bad "ask: $label" "expected ask, got '${got}' (exit=${HOOK_EXIT})"
}

assert_allow() {
    local label="$1" fixture="$2"
    run_hook "$fixture"
    # allow = exit 0 with no JSON output (or an explicit "allow" decision)
    local got; got="$(last_decision)"
    [ $HOOK_EXIT -eq 0 ] && [ "$got" = "allow" ] \
        && ok  "allow: $label" \
        || bad "allow: $label" "expected allow (exit 0, no deny/ask), got '${got}' exit=${HOOK_EXIT}"
}

# --------------------------------------------------------------------------- #
# 1. Deny: environment files
# --------------------------------------------------------------------------- #
assert_deny ".env (bare)"            "${CONTRACT}/pre-read-deny-env.json"
assert_deny ".env.production"        "${CONTRACT}/pre-read-deny-env-prod.json"

# --------------------------------------------------------------------------- #
# 2. Deny: private key / certificate material
# --------------------------------------------------------------------------- #
assert_deny "*.pem"                  "${CONTRACT}/pre-read-deny-pem.json"
assert_deny "id_rsa"                 "${CONTRACT}/pre-read-deny-id-rsa.json"

# --------------------------------------------------------------------------- #
# 3. Deny: credential stores
# --------------------------------------------------------------------------- #
assert_deny ".aws/credentials"       "${CONTRACT}/pre-read-deny-credentials.json"
assert_deny ".kube/config"           "${CONTRACT}/pre-read-deny-kube-config.json"
assert_deny "secrets/ directory"     "${CONTRACT}/pre-read-deny-secrets-dir.json"

# --------------------------------------------------------------------------- #
# 4. Allow: template env files (exception to the .env.* deny)
# --------------------------------------------------------------------------- #
assert_allow ".env.example"          "${CONTRACT}/pre-read-allow-env-example.json"
assert_allow ".env.dist"             "${CONTRACT}/pre-read-allow-env-dist.json"
assert_allow ".env.template"         "${CONTRACT}/pre-read-allow-env-template.json"

# --------------------------------------------------------------------------- #
# 5. Ask: Terraform variable files with sensitive names
# --------------------------------------------------------------------------- #
assert_ask   "*.tfvars (secret)"     "${CONTRACT}/pre-read-ask-tfvars-secret.json"
assert_ask   "*.tfvars (prod)"       "${CONTRACT}/pre-read-ask-tfvars-prod.json"

# --------------------------------------------------------------------------- #
# 6. Allow: plain Terraform variable file (no sensitive name)
# --------------------------------------------------------------------------- #
assert_allow "*.tfvars (plain dev)"  "${CONTRACT}/pre-read-allow-tfvars-plain.json"

# --------------------------------------------------------------------------- #
# 7. Inline edge cases (no fixture file needed)
# --------------------------------------------------------------------------- #

# .env.development should be denied (not a template exemption)
_json='{"session_id":"s","cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/p/.env.development"},"tool_use_id":"t1","agent_id":null,"agent_type":null}'
HOOK_OUTPUT="$(printf '%s' "$_json" | "$HOOK" 2>/dev/null)"
HOOK_EXIT=$?
_got="$(last_decision)"
[ "$_got" = "deny" ] \
    && ok  "deny: .env.development (not a template)" \
    || bad "deny: .env.development" "expected deny, got '${_got}'"

# id_ed25519 should be denied
_json='{"session_id":"s","cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/home/user/.ssh/id_ed25519"},"tool_use_id":"t2","agent_id":null,"agent_type":null}'
HOOK_OUTPUT="$(printf '%s' "$_json" | "$HOOK" 2>/dev/null)"
HOOK_EXIT=$?
_got="$(last_decision)"
[ "$_got" = "deny" ] \
    && ok  "deny: id_ed25519" \
    || bad "deny: id_ed25519" "expected deny, got '${_got}'"

# credentials.json (basename pattern) should be denied
_json='{"session_id":"s","cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/p/config/credentials.json"},"tool_use_id":"t3","agent_id":null,"agent_type":null}'
HOOK_OUTPUT="$(printf '%s' "$_json" | "$HOOK" 2>/dev/null)"
HOOK_EXIT=$?
_got="$(last_decision)"
[ "$_got" = "deny" ] \
    && ok  "deny: credentials.json (generic basename)" \
    || bad "deny: credentials.json" "expected deny, got '${_got}'"

# *.p12 should be denied
_json='{"session_id":"s","cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/p/certs/client.p12"},"tool_use_id":"t4","agent_id":null,"agent_type":null}'
HOOK_OUTPUT="$(printf '%s' "$_json" | "$HOOK" 2>/dev/null)"
HOOK_EXIT=$?
_got="$(last_decision)"
[ "$_got" = "deny" ] \
    && ok  "deny: *.p12" \
    || bad "deny: *.p12" "expected deny, got '${_got}'"

# production.tfvars should trigger ask (contains 'prod')
_json='{"session_id":"s","cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/p/infra/production.tfvars"},"tool_use_id":"t5","agent_id":null,"agent_type":null}'
HOOK_OUTPUT="$(printf '%s' "$_json" | "$HOOK" 2>/dev/null)"
HOOK_EXIT=$?
_got="$(last_decision)"
[ "$_got" = "ask" ] \
    && ok  "ask: production.tfvars" \
    || bad "ask: production.tfvars" "expected ask, got '${_got}'"

# missing file_path: should allow (no path = pass through)
_json='{"session_id":"s","cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{},"tool_use_id":"t6","agent_id":null,"agent_type":null}'
HOOK_OUTPUT="$(printf '%s' "$_json" | "$HOOK" 2>/dev/null)"
HOOK_EXIT=$?
[ $HOOK_EXIT -eq 0 ] \
    && ok  "allow: missing file_path → pass through" \
    || bad "allow: missing file_path" "expected exit 0, got ${HOOK_EXIT}"

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
