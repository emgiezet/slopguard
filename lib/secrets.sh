#!/usr/bin/env bash
# lib/secrets.sh — scan proposed content without ever printing secret values.

secret_in_content() {
    local content="$1" location="${2:-proposed content}"
    local scanner scanner_path rc fallback


    for scanner in betterleaks gitleaks; do
        scanner_path=""
        if declare -F resolve_tool >/dev/null 2>&1; then
            scanner_path="$(resolve_tool "$scanner" 2>/dev/null || true)"
        else
            scanner_path="$(command -v "$scanner" 2>/dev/null || true)"
        fi
        [ -n "$scanner_path" ] || continue
        printf '%s' "$content" | "$scanner_path" stdin \
            --report-format json --report-path - --redact --no-banner >/dev/null 2>&1
        rc=$?
        case "$rc" in
            0) return 1 ;;
            1)
                printf '%s\n' "${scanner} credential finding in ${location}"
                return 0
                ;;
            *) continue ;;
        esac
    done

    # Infrastructure failures are fail-open, but a small local fallback still blocks
    # unmistakable credentials while preserving the no-network fast path.
    fallback="-----BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|(^|[^[:alnum:]_])(aws_secret_access_key|api[_-]?key|client[_-]?secret|password)[[:space:]]*[:=][[:space:]]*[\"']?[^[:space:]\"']{8,}"
    if printf '%s' "$content" | grep -Eq -- "$fallback"; then
        printf '%s\n' "credential-like content in ${location}"
        return 0
    fi
    return 1
}
