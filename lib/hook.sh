#!/usr/bin/env bash
# lib/hook.sh — hook I/O contract: stdin decode, response encode, exit codes.
#
# §3.2: a hook receives JSON on stdin exactly once; read it here and cache it so
# nothing downstream consumes the stream (aisdlc:318-320 exists for this reason).
#
# Public interface:
#   hook_input               — read stdin once into _HOOK_INPUT (call at entry)
#   hook_field  <jq-path>    — extract a field; empty for null/missing
#   hook_deny   <reason>     — deny, or add context in advisory mode
#   hook_secret_deny <reason> — always deny secret access/content
#   hook_allow               — print permissionDecision:allow JSON to stdout
#   hook_context <text>      — print additionalContext JSON to stdout
#   hook_message <text>      — print systemMessage JSON to stdout
#
# Exit-code contract (§3.2):
#   exit 0 + JSON on stdout  — structured decision (use these helpers)
#   exit 2                   — blocking error; reason on stderr
#   exit 1 / other           — non-blocking; action proceeds
#
# All JSON is built with jq -n --arg; never by string-concatenating, because a
# reason containing a double-quote would emit invalid JSON and Claude would
# silently ignore the decision.
#
# additionalContext is written as a statement of fact, never as a system-style
# order — prompt-injection defences may trigger on imperative text (§3.2).


# SessionStart bootstraps jq into plugin data. Hook processes do not inherit the
# SessionStart process environment, so discover that managed binary explicitly.
if ! command -v jq >/dev/null 2>&1 && [ -x "${CLAUDE_PLUGIN_DATA:-}/tools/jq/current/jq" ]; then
    PATH="${CLAUDE_PLUGIN_DATA}/tools/jq/current:${PATH}"
    export PATH
fi
# Cache for the hook's stdin payload.
_HOOK_INPUT=""

# hook_input — read stdin once into _HOOK_INPUT.
# A hook gets exactly one shot at stdin; cache it immediately so later helpers
# can still call hook_field without a live stream.
hook_input() {
    _HOOK_INPUT="$(cat)"
}

# hook_field <jq-path>
# Extract a field from the cached hook payload.  Returns empty string for
# null or missing values so callers can use [ -z "$(hook_field .x)" ].
hook_field() {
    printf '%s' "$_HOOK_INPUT" | jq -r "${1} // empty"
}

# hook_deny <reason>
# Policy denial in balanced/strict mode; advisory mode reports context instead.
hook_deny() {
    if [ "${CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE:-balanced}" = "advisory" ]; then
        hook_context "$1"
    else
        hook_secret_deny "$1"
    fi
}

# hook_secret_deny <reason>
# Secrets are the sole advisory-mode exception and always fail closed.
hook_secret_deny() {
    jq -n --arg reason "$1" \
        '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason}}'
}

# hook_ask <reason>
# Ask interactively, deny when headless, or report context in advisory mode.
hook_ask() {
    local decision="ask" reason="$1"
    if [ "${CLAUDE_PLUGIN_OPTION_ENFORCEMENT_MODE:-balanced}" = "advisory" ]; then
        hook_context "$reason"
        return
    fi
    if [ "${AISDLC_HEADLESS:-0}" = "1" ]; then
        decision="deny"
        reason="${reason} — no human in this session"
    fi
    jq -n --arg decision "$decision" --arg reason "$reason" \
        '{"hookSpecificOutput":{"permissionDecision":$decision,"permissionDecisionReason":$reason}}'
}

# hook_allow
# Emit an explicit allow.  Usually omitted (default), but useful when a hook
# wants to record context without interfering.
hook_allow() {
    jq -n '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
}

# hook_context <text>
# Add context that Claude sees alongside the tool result (PreToolUse,
# PostToolUse, PostToolBatch) or at turn end (Stop).
# Write as a statement of fact, not as a command (§3.2).
hook_context() {
    jq -n --arg text "$1" \
        '{"hookSpecificOutput":{"additionalContext":$text}}'
}

# hook_message <text>
# Surface a warning visible to the user (systemMessage).
hook_message() {
    jq -n --arg text "$1" \
        '{"systemMessage":$text}'
}
