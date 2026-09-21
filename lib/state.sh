#!/usr/bin/env bash
# lib/state.sh — session state: directory layout, mkdir-based locking, pruning.
#
# §4.5 state layout:
#   ${CLAUDE_PLUGIN_DATA}/sessions/<session_id>[/<agent_id>]/
#     profile.json      — stacks, stacks_source, stacks_warnings, tools, config sources
#     touched.json      — files changed in the session with content hash
#     findings.json     — findings array (written atomically by finding_add)
#     stop-iterations   — stop-gate iteration counter (plain integer, default 0)
#     docs-lookups.json — Context7 documentation lookups for this agent (written atomically by docs_note)
#
# Locking (D1): mkdir "$dir/.lock" (best-effort) + noclobber tiebreaker
#   ( set -C; : > "$dir/.lock/owner" ) — O_EXCL open, atomic on all POSIX fs.
#
# Pruning: sessions older than 7 days removed at session-start (§4.5).

# --------------------------------------------------------------------------- #
# Path helpers
# --------------------------------------------------------------------------- #

# state_dir <session_id> [<agent_id>]
state_dir() {
    local session_id="$1"
    local agent_id="${2:-}"
    local base="${CLAUDE_PLUGIN_DATA}/sessions/${session_id}"
    if [ -n "$agent_id" ] && [ "$agent_id" != "--" ]; then
        printf '%s/%s' "$base" "$agent_id"
    else
        printf '%s' "$base"
    fi
}

# state_sessions_root — print the sessions root directory.
state_sessions_root() {
    printf '%s/sessions' "${CLAUDE_PLUGIN_DATA}"
}

# --------------------------------------------------------------------------- #
# Initialisation
# --------------------------------------------------------------------------- #

state_init() {
    local session_id="$1"
    local agent_id="${2:-}"
    local dir; dir="$(state_dir "$session_id" "$agent_id")"
    mkdir -p "$dir"
    [ -f "${dir}/profile.json" ]    || printf '{}\n'  > "${dir}/profile.json"
    [ -f "${dir}/touched.json" ]    || printf '{}\n'  > "${dir}/touched.json"
    [ -f "${dir}/findings.json" ]   || printf '[]\n'  > "${dir}/findings.json"
    [ -f "${dir}/stop-iterations" ] || printf '0\n'   > "${dir}/stop-iterations"
    [ -f "${dir}/docs-lookups.json" ] || printf '[]\n' > "${dir}/docs-lookups.json"
}

# --------------------------------------------------------------------------- #
# Locking
# --------------------------------------------------------------------------- #

# _stat_mtime <path>
_stat_mtime() {
    local mtime
    mtime=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)
    if [[ "$mtime" =~ ^[0-9]+$ ]]; then
        printf '%s' "$mtime"
    fi
}

# state_lock_acquire <dir> [<max_retries> [<stale_age_seconds>]]
# Acquire an exclusive lock on <dir>.
# Strategy: mkdir creates the lock directory (best-effort; not atomic on all
# implementations), then a noclobber redirect atomically claims ownership.
# Only the process that creates .lock/owner holds the lock.
state_lock_acquire() {
    local dir="$1"
    local max_retries="${2:-50}"
    local stale_age="${3:-60}"
    local lockdir="${dir}/.lock"
    local attempt=0
    while [ "$attempt" -lt "$max_retries" ]; do
        mkdir "$lockdir" 2>/dev/null || true
        # O_EXCL tiebreaker: only one process can create the owner file.
        if ( set -C; : > "${lockdir}/owner" ) 2>/dev/null; then
            return 0
        fi

        # Detect and remove a stale lock.
        if [ -d "$lockdir" ]; then
            local now; now="$(date +%s)"
            local mtime; mtime="$(_stat_mtime "$lockdir")"
            if [ -n "$mtime" ] && [ "$((now - mtime))" -gt "$stale_age" ]; then
                rm -rf "$lockdir" 2>/dev/null || true
            fi
        fi
        attempt=$((attempt + 1))
        sleep "0.0$((RANDOM % 9 + 1))"
    done
    return 1
}

# state_lock_release <dir>
state_lock_release() {
    rm -f "${1}/.lock/owner" 2>/dev/null || true
    rmdir "${1}/.lock" 2>/dev/null || true
}

# --------------------------------------------------------------------------- #
# Pruning
# --------------------------------------------------------------------------- #

state_prune() {
    local root; root="$(state_sessions_root)"
    [ -d "$root" ] || return 0
    local cutoff; cutoff="$(($(date +%s) - 7 * 24 * 3600))"
    local session_dir
    for session_dir in "${root}"/*/; do
        [ -d "$session_dir" ] || continue
        local mtime; mtime="$(_stat_mtime "$session_dir")"
        [ -n "$mtime" ] || continue
        if [ "$mtime" -lt "$cutoff" ]; then
            rm -rf "$session_dir"
        fi
    done
}
