#!/usr/bin/env bash
# hook_test.sh — tests for lib/hook.sh: stdin decode, response encode, exit codes.
#
# Sourced by tests/run-tests; ok() and bad() are pre-defined there.
# Contract payloads live in tests/hook-contract/.

HOOK_TEST_WORK="${TMPDIR:-/tmp}/slop-guard-hook-test-$$"
mkdir -p "$HOOK_TEST_WORK"
trap 'rm -rf "${HOOK_TEST_WORK}"' EXIT INT TERM

# shellcheck source=../lib/hook.sh
. "${PLUGIN_ROOT}/lib/hook.sh"

CONTRACT="${PLUGIN_ROOT}/tests/hook-contract"

# --------------------------------------------------------------------------- #
# 1. hook_input: reads stdin into _HOOK_INPUT
# --------------------------------------------------------------------------- #
_HOOK_INPUT=""
hook_input <<'__JSON__'
{"session_id":"from-stdin","hook_event_name":"PreToolUse"}
__JSON__
val="$(hook_field .session_id)"
[ "$val" = "from-stdin" ] \
    && ok  "hook_input: reads stdin into _HOOK_INPUT" \
    || bad "hook_input: reads stdin into _HOOK_INPUT" "got: $val"

# --------------------------------------------------------------------------- #
# 2. PreToolUse(Bash): field extraction
# --------------------------------------------------------------------------- #
_HOOK_INPUT="$(cat "${CONTRACT}/pre-tool-bash.json")"

val="$(hook_field .session_id)"
[ "$val" = "sess-abc123" ] \
    && ok  "bash: .session_id" || bad "bash: .session_id" "$val"

val="$(hook_field .cwd)"
[ "$val" = "/home/user/myproject" ] \
    && ok  "bash: .cwd" || bad "bash: .cwd" "$val"

val="$(hook_field .hook_event_name)"
[ "$val" = "PreToolUse" ] \
    && ok  "bash: .hook_event_name" || bad "bash: .hook_event_name" "$val"

val="$(hook_field .tool_name)"
[ "$val" = "Bash" ] \
    && ok  "bash: .tool_name" || bad "bash: .tool_name" "$val"

val="$(hook_field .tool_use_id)"
[ "$val" = "toolu_bash_0001" ] \
    && ok  "bash: .tool_use_id" || bad "bash: .tool_use_id" "$val"

# Bash has no file_path; hook_field returns empty for null/missing
val="$(hook_field .tool_input.file_path)"
[ -z "$val" ] \
    && ok  "bash: .tool_input.file_path → empty (no path)" \
    || bad "bash: .tool_input.file_path → empty" "got: $val"

# agent_id is null in the main session
val="$(hook_field .agent_id)"
[ -z "$val" ] \
    && ok  "bash: .agent_id null → empty" \
    || bad "bash: .agent_id null → empty" "got: $val"

# --------------------------------------------------------------------------- #
# 3. PreToolUse(Write): file_path extraction
# --------------------------------------------------------------------------- #
_HOOK_INPUT="$(cat "${CONTRACT}/pre-tool-write.json")"

val="$(hook_field .tool_name)"
[ "$val" = "Write" ] \
    && ok  "write: .tool_name" || bad "write: .tool_name" "$val"

val="$(hook_field .tool_input.file_path)"
[ "$val" = "/home/user/myproject/secret.py" ] \
    && ok  "write: .tool_input.file_path" || bad "write: .tool_input.file_path" "$val"

# --------------------------------------------------------------------------- #
# 4. PreToolUse(Edit): file_path + subagent fields
# --------------------------------------------------------------------------- #
_HOOK_INPUT="$(cat "${CONTRACT}/pre-tool-edit.json")"

val="$(hook_field .tool_name)"
[ "$val" = "Edit" ] \
    && ok  "edit: .tool_name" || bad "edit: .tool_name" "$val"

val="$(hook_field .tool_input.file_path)"
[ "$val" = "/home/user/myproject/app.py" ] \
    && ok  "edit: .tool_input.file_path" || bad "edit: .tool_input.file_path" "$val"

val="$(hook_field .agent_id)"
[ "$val" = "agent-sub-1" ] \
    && ok  "edit: .agent_id (subagent)" || bad "edit: .agent_id" "$val"

val="$(hook_field .agent_type)"
[ "$val" = "subagent" ] \
    && ok  "edit: .agent_type" || bad "edit: .agent_type" "$val"

# --------------------------------------------------------------------------- #
# 5. Stop event: stop_hook_active
# --------------------------------------------------------------------------- #
_HOOK_INPUT="$(cat "${CONTRACT}/stop-active.json")"

val="$(hook_field .hook_event_name)"
[ "$val" = "Stop" ] \
    && ok  "stop: .hook_event_name" || bad "stop: .hook_event_name" "$val"

val="$(hook_field .stop_hook_active)"
[ "$val" = "true" ] \
    && ok  "stop: .stop_hook_active = true" || bad "stop: .stop_hook_active" "$val"

# tool_name is null for Stop
val="$(hook_field .tool_name)"
[ -z "$val" ] \
    && ok  "stop: .tool_name null → empty" || bad "stop: .tool_name null" "$val"

# --------------------------------------------------------------------------- #
# 6. Encoders: correct JSON output (key order irrelevant; compare via jq -S .)
# --------------------------------------------------------------------------- #
_cmp_json() {
    # _cmp_json <label> <actual> <expected-inline>
    local label="$1" actual="$2" expected="$3"
    local norm_actual norm_expected
    norm_actual="$(printf '%s' "$actual"   | jq -S .)"
    norm_expected="$(printf '%s' "$expected" | jq -S .)"
    if [ "$norm_actual" = "$norm_expected" ]; then
        ok "$label"
    else
        bad "$label" "got: $actual"
    fi
}

_cmp_json "hook_deny: permissionDecision=deny JSON" \
    "$(hook_deny "blocked by policy")" \
    '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"blocked by policy"}}'

_cmp_json "hook_ask: permissionDecision=ask JSON" \
    "$(hook_ask "please confirm")" \
    '{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":"please confirm"}}'

_cmp_json "hook_allow: permissionDecision=allow JSON" \
    "$(hook_allow)" \
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'

_cmp_json "hook_context: additionalContext JSON" \
    "$(hook_context "analysis complete: 0 issues found")" \
    '{"hookSpecificOutput":{"additionalContext":"analysis complete: 0 issues found"}}'

_cmp_json "hook_message: systemMessage JSON" \
    "$(hook_message "1 blocker found in changed code")" \
    '{"systemMessage":"1 blocker found in changed code"}'

# --------------------------------------------------------------------------- #
# 7. Special characters: reason with " and $ must survive JSON round-trip
# --------------------------------------------------------------------------- #
TRICKY='contains "quotes" and $dollars are safe'

actual="$(hook_deny "$TRICKY")"
parsed="$(printf '%s' "$actual" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
[ "$parsed" = "$TRICKY" ] \
    && ok  "hook_deny: double-quote + dollar survive round-trip" \
    || bad "hook_deny: special chars" "got: $parsed"

actual="$(hook_ask "$TRICKY")"
parsed="$(printf '%s' "$actual" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
[ "$parsed" = "$TRICKY" ] \
    && ok  "hook_ask: double-quote + dollar survive round-trip" \
    || bad "hook_ask: special chars" "got: $parsed"

actual="$(hook_context "$TRICKY")"
parsed="$(printf '%s' "$actual" | jq -r '.hookSpecificOutput.additionalContext')"
[ "$parsed" = "$TRICKY" ] \
    && ok  "hook_context: double-quote + dollar survive round-trip" \
    || bad "hook_context: special chars" "got: $parsed"

# --------------------------------------------------------------------------- #
# 8. Headless asks fail closed with the original reason preserved
# --------------------------------------------------------------------------- #
actual="$(AISDLC_HEADLESS=1 hook_ask "please confirm")"
decision="$(printf '%s' "$actual" | jq -r '.hookSpecificOutput.permissionDecision')"
parsed="$(printf '%s' "$actual" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
[ "$decision" = "deny" ] && [ "$parsed" = "please confirm — no human in this session" ] \
    && ok  "hook_ask: headless session denies with reason" \
    || bad "hook_ask: headless session" "decision=${decision}, reason=${parsed}"

# --------------------------------------------------------------------------- #
# 9. Advisory mode reports policy decisions but never relaxes secret blocks
# --------------------------------------------------------------------------- #
_cmp_json "hook_deny: advisory emits context" \
    "$(CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=advisory hook_deny "blocked by policy")" \
    '{"hookSpecificOutput":{"additionalContext":"blocked by policy"}}'

_cmp_json "hook_ask: advisory emits context" \
    "$(CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=advisory hook_ask "please confirm")" \
    '{"hookSpecificOutput":{"additionalContext":"please confirm"}}'

_cmp_json "hook_secret_deny: advisory still denies" \
    "$(CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE=advisory hook_secret_deny "secret found")" \
    '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"secret found"}}'
