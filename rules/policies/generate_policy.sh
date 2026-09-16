#!/usr/bin/env bash
# Convert the repository-owned bash.yaml subset into shell arrays.
set -eu

policy="${1:?usage: generate_policy.sh POLICY}"

emit_array() {
    local name="$1" section="$2"
    printf '%s=(' "$name"
    awk -v section="$section" '
        $0 == section ":" { active = 1; next }
        active && /^[[:alnum:]_]+:/ { exit }
        active && /^[[:space:]]*pattern:/ {
            value = $0
            sub(/^[[:space:]]*pattern:[[:space:]]*\047/, "", value)
            sub(/\047[[:space:]]*$/, "", value)
            print value
        }
    ' "$policy" | while IFS= read -r pattern; do
        printf ' %q' "$pattern"
    done
    printf ' )\n'
}

emit_array ALLOW_PATTERNS allow
emit_array DENY_PATTERNS deny
emit_array ASK_PATTERNS ask
