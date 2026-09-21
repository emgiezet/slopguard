#!/usr/bin/env bash
# lib/docs.sh — Context7 documentation lookup tracing.
#
# Requires: lib/state.sh (state_dir, state_lock_acquire, state_lock_release)
#           sourced in the calling script before this file.
#
# Public interface:
#   docs_note    <session_id> <agent_id> <library>  — record a lookup; dedupe by library
#   docs_seen    <session_id> <agent_id> <library>  — exit 0 when recorded
#   docs_remember <library> <version>               — write cross-session memory file
#   docs_recall   <library> <version>               — exit 0 when memory file present
#
# Writes are atomic (mktemp + mv). A corrupt or absent docs-lookups.json
# degrades to [] — a broken trace file must never break a hook.

# _docs_file <session_id> <agent_id>
# Print the absolute path to docs-lookups.json for this session/agent.
_docs_file() {
    printf '%s/docs-lookups.json' "$(state_dir "$1" "$2")"
}

# _docs_read <path>
# Read the docs-lookups.json at <path>.  Returns [] when absent or corrupt.
_docs_read() {
    local raw=""
    [ -f "$1" ] && raw="$(cat "$1" 2>/dev/null || true)"
    jq 'if type == "array" then . else [] end' <<< "${raw:-[]}" 2>/dev/null \
        || printf '[]'
}

# docs_note <session_id> <agent_id> <library>
# Record a lookup in docs-lookups.json.  Deduplicates by library using the
# same case-insensitive substring logic as docs_seen.
docs_note() {
    local session_id="$1" agent_id="$2" library="$3"
    [ -z "$library" ] && return 0

    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    mkdir -p "$dir"

    local f; f="${dir}/docs-lookups.json"

    # Acquire the exclusive lock on the session directory.
    if ! state_lock_acquire "$dir"; then
        printf 'slopguard: docs_note: lock timeout for %s\n' "$dir" >&2
        return 1
    fi

    # Read current contents under lock; initialise if absent.
    [ -f "$f" ] || printf '[]\n' > "$f"
    local current; current="$(_docs_read "$f")"

    # Duplicate check (case-insensitive, substring-tolerant).
    local needle; needle="$(printf '%s' "$library" | tr '[:upper:]' '[:lower:]')"
    local libs; libs="$(jq -r '.[].library' <<< "$current")"
    local already=0
    local rec
    while IFS= read -r rec; do
        [ -z "$rec" ] && continue
        local hay; hay="$(printf '%s' "$rec" | tr '[:upper:]' '[:lower:]')"
        case "$hay" in *"$needle"*) already=1; break ;; esac
        case "$needle" in *"$hay"*) already=1; break ;; esac
    done <<< "$libs"

    if [ "$already" -eq 0 ]; then
        local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        local tmp; tmp="$(mktemp "${dir}/.docs-lookups.XXXXXX")"
        local jq_ok=0
        jq --arg lib "$library" --arg ts "$ts" \
            '. + [{"library": $lib, "ts": $ts}]' <<< "$current" > "$tmp" \
            || jq_ok=$?
        if [ "$jq_ok" -eq 0 ]; then
            mv "$tmp" "$f"
        else
            rm -f "$tmp"
            printf 'slopguard: docs_note: jq failed with %d\n' "$jq_ok" >&2
        fi
    fi

    state_lock_release "$dir"
}

# docs_seen <session_id> <agent_id> <library>
# Exit 0 when <library> has been noted.
# Matching is case-insensitive and substring-tolerant in both directions:
#   'laravel' matches '/laravel/laravel' and vice versa.
docs_seen() {
    local session_id="$1" agent_id="$2" library="$3"
    local needle; needle="$(printf '%s' "$library" | tr '[:upper:]' '[:lower:]')"

    local f; f="$(_docs_file "$session_id" "$agent_id")"
    local entries; entries="$(_docs_read "$f")"
    local libs; libs="$(jq -r '.[].library' <<< "$entries")"

    local rec
    while IFS= read -r rec; do
        [ -z "$rec" ] && continue
        local hay; hay="$(printf '%s' "$rec" | tr '[:upper:]' '[:lower:]')"
        case "$hay" in *"$needle"*) return 0 ;; esac
        case "$needle" in *"$hay"*) return 0 ;; esac
    done <<< "$libs"

    return 1
}

# _docs_memory_dir — cross-session memory directory.
_docs_memory_dir() {
    printf '%s/docs-seen' "${CLAUDE_PLUGIN_DATA}"
}

# _docs_key <library> <version>
# Produce a safe filename component: sanitised library + @<major>.<minor>.
# Characters outside [A-Za-z0-9._-] in the library string are replaced with -.
# A leading 'v'/'V' on the version is stripped before parsing major.minor.
_docs_key() {
    local library="$1" version="$2"
    local safe_lib; safe_lib="$(printf '%s' "$library" | tr -c 'A-Za-z0-9._-' '-')"
    local v; v="${version#[vV]}"
    local major; major="$(printf '%s' "$v" | cut -d. -f1)"
    local minor; minor="$(printf '%s' "$v" | cut -d. -f2)"
    printf '%s@%s.%s' "$safe_lib" "${major:-0}" "${minor:-0}"
}

# docs_remember <library> <version>
# Write a timestamped marker in ${CLAUDE_PLUGIN_DATA}/docs-seen/<library>@<major>.<minor>
# recording that documentation was consulted for this library at this version.
docs_remember() {
    local library="$1" version="$2"
    local mdir; mdir="$(_docs_memory_dir)"
    mkdir -p "$mdir"
    local key; key="$(_docs_key "$library" "$version")"
    local f="${mdir}/${key}"
    local tmp; tmp="$(mktemp "${mdir}/.docs-seen.XXXXXX")"
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp" && mv "$tmp" "$f"
}

# docs_recall <library> <version>
# Exit 0 when docs_remember was called with the same library at the same
# <major>.<minor>. Exit 1 when no memory file is present.
docs_recall() {
    local library="$1" version="$2"
    local key; key="$(_docs_key "$library" "$version")"
    [ -f "$(_docs_memory_dir)/${key}" ]
}
