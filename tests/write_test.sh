#!/usr/bin/env bash
# write_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.

WRITE_HOOK="${PLUGIN_ROOT}/hooks/pre-write"
# Provide CLAUDE_PLUGIN_DATA for standalone invocation; run-tests has state_test.sh
# export it already.  Track ownership to clean up only what we created.
_WRITE_OWN_DATA=false
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
    export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/slop-guard-write-test-$$"
    mkdir -p "${CLAUDE_PLUGIN_DATA}/sessions"
    _WRITE_OWN_DATA=true
fi


run_write_policy() {
    local tool="$1" file="$2" new_content="$3" old_content="$4" expected="$5" label="$6"
    local output decision
    output="$(jq -n \
        --arg tool "$tool" --arg file "$file" --arg new "$new_content" --arg old "$old_content" \
        '{tool_name:$tool,tool_input:{file_path:$file,content:$new,new_string:$new,old_string:$old}}' \
        | "$WRITE_HOOK")"
    if [ -n "$output" ]; then
        decision="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')"
    else
        decision="allow"
    fi
    [ "$decision" = "$expected" ] \
        && ok "pre-write: $label" \
        || bad "pre-write: $label" "expected $expected, got $decision"
}

run_write_policy Write app.go '//nolint:gosec' '' deny 'suppression without reason denied'
run_write_policy Write app.go '//nolint:gosec // reason: input validated upstream' '' allow 'suppression with configured reason allowed'
run_write_policy Edit app.go '//nolint:gosec' '//nolint:gosec' allow 'unchanged suppression remains editable'
run_write_policy Edit app.py 'x = g()  # noqa' 'x = f()  # noqa' allow 'existing suppression survives line edit'
run_write_policy Write app.py 'api_key = "1234567890abcdef"' '' deny 'obvious secret denied'
run_write_policy Write app.py 'token = "ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"' '' deny 'GitHub token denied'
scanner_project="${TMPDIR:-/tmp}/slop-guard-scanner-project-$$"
mkdir -p "${scanner_project}/vendor/bin"
cat > "${scanner_project}/vendor/bin/betterleaks" <<'EOF'
#!/bin/sh
cat >/dev/null
exit 1
EOF
chmod +x "${scanner_project}/vendor/bin/betterleaks"
scanner_output="$(jq -n \
    '{tool_name:"Write",tool_input:{file_path:"scanner.py",content:"scanner-only-marker"}}' \
    | CLAUDE_PROJECT_DIR="$scanner_project" CLAUDE_PLUGIN_OPTION_TOOL_SOURCE=project-first "$WRITE_HOOK")"
scanner_reason="$(printf '%s' "$scanner_output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
[ "$(printf '%s' "$scanner_output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ] \
    && printf '%s' "$scanner_reason" | grep -qF 'betterleaks credential finding in scanner.py' \
    && ok 'pre-write: managed secret scanner blocks with redacted location' \
    || bad 'pre-write: managed secret scanner' "$scanner_output"
rm -rf "$scanner_project"
notebook_output="$(jq -n \
    '{tool_name:"NotebookEdit",tool_input:{notebook_path:"analysis.ipynb",new_source:"token = \"ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"",old_source:""}}' \
    | "$WRITE_HOOK")"
[ "$(printf '%s' "$notebook_output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ] \
    && ok 'pre-write: NotebookEdit new_source is scanned' \
    || bad 'pre-write: NotebookEdit new_source' "$notebook_output"
run_write_policy Edit phpstan-baseline.neon 'parameters: {}' 'parameters: {}' ask 'protected baseline asks'
run_write_policy Edit pyproject.toml '' '[tool.ruff]' ask 'removing protected pyproject section asks'
run_write_policy Edit tsconfig.json '' '"strict": true' ask 'removing strict TypeScript config asks'
run_write_policy Write .slopguard.json '{"stacks":[]}' '' ask '.slopguard.json write asks'
run_write_policy Write package.json '{"name":"app"}' '' allow 'package.json write is not blocked'

context_payload="$(jq -n \
    '{session_id:"write-context",tool_name:"Write",tool_input:{file_path:"context.py",content:"print(1)"}}')"
first_context="$(printf '%s' "$context_payload" | "$WRITE_HOOK")"
second_context="$(printf '%s' "$context_payload" | "$WRITE_HOOK")"
context_text="$(printf '%s' "$first_context" | jq -r '.hookSpecificOutput.additionalContext // empty')"
[ -n "$context_text" ] && [ -z "$second_context" ] \
    && ok 'pre-write: language blocker context appears once' \
    || bad 'pre-write: language blocker context' "first=${first_context}, second=${second_context}"

output="$(jq -n --arg file 'eslint.config.js' --arg new 'export default {}' \
    '{tool_name:"Write",tool_input:{file_path:$file,content:$new}}' \
    | AISDLC_HEADLESS=1 "$WRITE_HOOK")"
decision="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')"
reason="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
[ "$decision" = deny ] && printf '%s' "$reason" | grep -qF 'no human in this session' \
    && ok 'pre-write: headless protected edit becomes reasoned deny' \
    || bad 'pre-write: headless protected edit' "decision=${decision}, reason=${reason}"
# Framework context in first-edit message
# Set up isolated state dir + profile.json with framework_versions.laravel,
# and a stacks.json that carries the context7 field for laravel.
_fw_w_data="${TMPDIR:-/tmp}/slop-guard-fw-write-$$"
mkdir -p "${_fw_w_data}"
jq '.laravel += {"context7": "laravel"}' "${PLUGIN_ROOT}/rules/stacks.json" \
    > "${_fw_w_data}/stacks.json"

_fw_w_sess="fw-write-ctx-$$"
_fw_w_sess_dir="${_fw_w_data}/sessions/${_fw_w_sess}"
mkdir -p "${_fw_w_sess_dir}"
printf '{"stacks":["php","laravel"],"stacks_source":"auto","stacks_warnings":[],"tools":[],"config_sources":{},"framework_versions":{"laravel":"v12.4.1"}}\n' \
    > "${_fw_w_sess_dir}/profile.json"

_fw_w_first="$(jq -n --arg sid "${_fw_w_sess}" \
    '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"app/Controller.php",content:"<?php"}}' \
    | CLAUDE_PLUGIN_DATA="${_fw_w_data}" SLOPGUARD_STACKS_JSON="${_fw_w_data}/stacks.json" \
      "${WRITE_HOOK}")"
_fw_w_ctx="$(printf '%s' "${_fw_w_first}" | jq -r '.hookSpecificOutput.additionalContext // empty')"
printf '%s' "${_fw_w_ctx}" | grep -q 'laravel' \
    && printf '%s' "${_fw_w_ctx}" | grep -q 'v12.4.1' \
    && printf '%s' "${_fw_w_ctx}" | grep -q 'mcp__context7__resolve-library-id' \
    && ok  'pre-write: laravel version and Context7 call appear in first PHP edit' \
    || bad 'pre-write: laravel framework context' "ctx=${_fw_w_ctx}"

# Second edit of another PHP file in same session — no repeat of framework context.
_fw_w_second="$(jq -n --arg sid "${_fw_w_sess}" \
    '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"app/Model.php",content:"<?php"}}' \
    | CLAUDE_PLUGIN_DATA="${_fw_w_data}" SLOPGUARD_STACKS_JSON="${_fw_w_data}/stacks.json" \
      "${WRITE_HOOK}")"
_fw_w_ctx2="$(printf '%s' "${_fw_w_second}" | jq -r '.hookSpecificOutput.additionalContext // empty')"
[ -z "${_fw_w_ctx2}" ] \
    && ok  'pre-write: second PHP edit in same session omits framework context' \
    || bad 'pre-write: second PHP edit framework repeat' "ctx=${_fw_w_ctx2}"

# REQUIRE_DOCS_LOOKUP=false — blocker sentence present, framework sentence absent.
_fw_w_nodocs_sess="fw-nodocs-$$"
_fw_w_nodocs_dir="${_fw_w_data}/sessions/${_fw_w_nodocs_sess}"
mkdir -p "${_fw_w_nodocs_dir}"
printf '{"stacks":["php","laravel"],"stacks_source":"auto","stacks_warnings":[],"tools":[],"config_sources":{},"framework_versions":{"laravel":"v12.4.1"}}\n' \
    > "${_fw_w_nodocs_dir}/profile.json"
_fw_w_nodocs="$(jq -n --arg sid "${_fw_w_nodocs_sess}" \
    '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"Service.php",content:"<?php"}}' \
    | CLAUDE_PLUGIN_DATA="${_fw_w_data}" SLOPGUARD_STACKS_JSON="${_fw_w_data}/stacks.json" \
      CLAUDE_PLUGIN_OPTION_REQUIRE_DOCS_LOOKUP=false "${WRITE_HOOK}")"
_fw_w_nodocs_ctx="$(printf '%s' "${_fw_w_nodocs}" | jq -r '.hookSpecificOutput.additionalContext // empty')"
printf '%s' "${_fw_w_nodocs_ctx}" | grep -q 'blocker checks cover' \
    && ! printf '%s' "${_fw_w_nodocs_ctx}" | grep -q 'mcp__context7' \
    && ok  'pre-write: REQUIRE_DOCS_LOOKUP=false suppresses framework sentence while keeping blockers' \
    || bad 'pre-write: REQUIRE_DOCS_LOOKUP=false' "ctx=${_fw_w_nodocs_ctx}"


# In-session suppression via docs_seen: agent noted lookup in same session.
# Create the session dir, run note-docs WITHOUT profile.json (so docs_remember is
# not triggered), THEN add profile.json so pre-write can find framework_versions.
_fw_seen_sess="fw-seen-$$"
_fw_seen_sdir="${_fw_w_data}/sessions/${_fw_seen_sess}"
mkdir -p "${_fw_seen_sdir}"

# docs_note for session; no profile.json → docs_remember skipped.
jq -n --arg sid "${_fw_seen_sess}" \
    '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"mcp__context7__get-library-docs",
      tool_input:{context7CompatibleLibraryID:"laravel"}}' \
    | CLAUDE_PLUGIN_DATA="${_fw_w_data}" \
      CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
      SLOPGUARD_STACKS_JSON="${_fw_w_data}/stacks.json" \
      "${PLUGIN_ROOT}/bin/slopguard" note-docs

# Now add profile.json so pre-write resolves the framework.
printf '{"stacks":["php","laravel"],"stacks_source":"auto","stacks_warnings":[],"tools":[],"config_sources":{},"framework_versions":{"laravel":"v12.4.1"}}\n' \
    > "${_fw_seen_sdir}/profile.json"

_fw_seen_out="$(jq -n --arg sid "${_fw_seen_sess}" \
    '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"app/Repo.php",content:"<?php"}}' \
    | CLAUDE_PLUGIN_DATA="${_fw_w_data}" SLOPGUARD_STACKS_JSON="${_fw_w_data}/stacks.json" \
      "${WRITE_HOOK}")"
_fw_seen_ctx="$(printf '%s' "${_fw_seen_out}" | jq -r '.hookSpecificOutput.additionalContext // empty')"
printf '%s' "${_fw_seen_ctx}" | grep -q 'blocker checks cover' \
    && ! printf '%s' "${_fw_seen_ctx}" | grep -q 'mcp__context7__resolve-library-id' \
    && ok  'pre-write: in-session docs_seen suppresses framework sentence, blockers remain' \
    || bad 'pre-write: in-session docs_seen suppression' "ctx=${_fw_seen_ctx}"

# Cross-session suppression via docs_recall: memory written in a prior session.
# Use a helper session with profile.json so note-docs triggers docs_remember.
_fw_ci_sess="fw-cross-init-$$"
_fw_ci_sdir="${_fw_w_data}/sessions/${_fw_ci_sess}"
mkdir -p "${_fw_ci_sdir}"
printf '{"stacks":["php","laravel"],"stacks_source":"auto","stacks_warnings":[],"tools":[],"config_sources":{},"framework_versions":{"laravel":"v12.4.1"}}\n' \
    > "${_fw_ci_sdir}/profile.json"

jq -n --arg sid "${_fw_ci_sess}" \
    '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"mcp__context7__get-library-docs",
      tool_input:{context7CompatibleLibraryID:"/laravel/laravel"}}' \
    | CLAUDE_PLUGIN_DATA="${_fw_w_data}" \
      CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
      SLOPGUARD_STACKS_JSON="${_fw_w_data}/stacks.json" \
      "${PLUGIN_ROOT}/bin/slopguard" note-docs

# Fresh session: no prior note-docs; docs_recall hits from the memory above.
_fw_recall_sess="fw-recall-$$"
_fw_recall_sdir="${_fw_w_data}/sessions/${_fw_recall_sess}"
mkdir -p "${_fw_recall_sdir}"
printf '{"stacks":["php","laravel"],"stacks_source":"auto","stacks_warnings":[],"tools":[],"config_sources":{},"framework_versions":{"laravel":"v12.4.1"}}\n' \
    > "${_fw_recall_sdir}/profile.json"

_fw_recall_out="$(jq -n --arg sid "${_fw_recall_sess}" \
    '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"app/Svc.php",content:"<?php"}}' \
    | CLAUDE_PLUGIN_DATA="${_fw_w_data}" SLOPGUARD_STACKS_JSON="${_fw_w_data}/stacks.json" \
      "${WRITE_HOOK}")"
_fw_recall_ctx="$(printf '%s' "${_fw_recall_out}" | jq -r '.hookSpecificOutput.additionalContext // empty')"
printf '%s' "${_fw_recall_ctx}" | grep -q 'blocker checks cover' \
    && ! printf '%s' "${_fw_recall_ctx}" | grep -q 'mcp__context7__resolve-library-id' \
    && ok  'pre-write: cross-session docs_recall suppresses framework sentence, blockers remain' \
    || bad 'pre-write: cross-session docs_recall suppression' "ctx=${_fw_recall_ctx}"

rm -rf "${_fw_w_data}"
if [ "$_WRITE_OWN_DATA" = true ]; then
    rm -rf "${CLAUDE_PLUGIN_DATA}"
fi
