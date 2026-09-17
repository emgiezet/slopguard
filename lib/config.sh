#!/usr/bin/env bash
# lib/config.sh — .slopguard.json resolution: stack-config layer.
#
# Precondition: lib/detect.sh must already be sourced by the caller (provides
#   detect_stacks, stacks_all, stack_known, stack_tier, and exports
#   SLOPGUARD_STACKS_JSON).  This file sources nothing itself.
#
# Public interface:
#   config_resolve_stacks <root>
#     Sets three globals; returns 0 always (fail-safe on any error).
#     SG_STACKS          — space-separated resolved stack tags
#     SG_STACKS_SOURCE   — auto | file | file-paths
#     SG_STACKS_WARNINGS — newline-separated warning strings (empty when none)
#
# Config path override: export SLOPGUARD_CONFIG_FILE=<path>
#   Default is <root>/.slopguard.json, re-evaluated on every call.
#
# requires gating (from stacks.json) is NOT applied to explicit file lists;
# explicit stacks are taken literally.  implies IS applied: a helm entry in the
# file still causes kubernetes to be added.
#
# "paths" values are declarative: the listed tags are applied verbatim for that
# subtree.  Autodetection is never run inside a declared path — the field exists
# precisely for subtrees whose manifests the root-level detection cannot see.
#
# Implementation note: all jq output is captured into a variable first, then
# fed into while loops via here-string (<<< "$var").  This avoids a jaq
# compatibility issue where a pipeline inside a process substitution stalls.

# --------------------------------------------------------------------------- #
# Internal helpers
# --------------------------------------------------------------------------- #

# _config_warn <message>
# Append one warning line to the global SG_STACKS_WARNINGS (newline-separated).
_config_warn() {
    if [ -z "$SG_STACKS_WARNINGS" ]; then
        SG_STACKS_WARNINGS="$1"
    else
        SG_STACKS_WARNINGS="${SG_STACKS_WARNINGS}
${1}"
    fi
}

# _config_implies <stacks>
# Expand a space-separated <stacks> set by reading each tag's implies[] array
# from stacks.json and unioning in the results (one pass).
# Reads SLOPGUARD_STACKS_JSON (exported by lib/detect.sh when sourced).
# Prints the expanded space-separated set; emits no warnings.
_config_implies() {
    local stacks="$1" tag implied result="$1" _imp_out
    # shellcheck disable=SC2086
    for tag in $stacks; do
        _imp_out="$(jq -r --arg t "$tag" \
            '.[$t].implies // [] | .[]' \
            "$SLOPGUARD_STACKS_JSON" 2>/dev/null)"
        while IFS= read -r implied; do
            [ -n "$implied" ] || continue
            result="$(_detect_add "$result" "$implied")"
        done <<< "$_imp_out"
    done
    printf '%s' "$result"
}

# _config_order <stacks>
# Re-order a space-separated <stacks> set to match stacks.json key (insertion)
# order via keys_unsorted.  Tags absent from stacks.json are appended in their
# original order (safety fallback; should not occur after stack_known validation).
_config_order() {
    local stacks="$1" tag result="" _keys_out
    _keys_out="$(jq -r 'keys_unsorted[]' "$SLOPGUARD_STACKS_JSON" 2>/dev/null)"
    while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        case " $stacks " in
            *" $tag "*) result="${result:+$result }$tag" ;;
        esac
    done <<< "$_keys_out"
    # Append anything not covered by stacks.json (stale JSON edge case).
    # shellcheck disable=SC2086
    for tag in $stacks; do
        case " $result " in
            *" $tag "*) ;;
            *) result="${result:+$result }$tag" ;;
        esac
    done
    printf '%s' "$result"
}

# _config_union <set-a> <set-b>
# Union two space-separated sets; deduplicates; <set-b> extras appended after <set-a>.
_config_union() {
    local result="$1" tag
    # shellcheck disable=SC2086
    for tag in $2; do
        result="$(_detect_add "$result" "$tag")"
    done
    printf '%s' "$result"
}

# --------------------------------------------------------------------------- #
# Public
# --------------------------------------------------------------------------- #

# config_resolve_stacks <root>
# Resolve stacks for the project at <root>.  Consults <root>/.slopguard.json
# (or SLOPGUARD_CONFIG_FILE override).  Sets three globals; returns 0 always.
config_resolve_stacks() {
    local root="${1:-.}"
    local _cfg _json _has_stacks _has_paths _src
    local _explicit_tags="" _paths_tags=""
    local _stacks_type _stacks_tags _t
    local _paths_type _paths_keys _p _p_type _p_tags
    local _all_tags _valid_all _tag _validated="" _implied _final="" _it
    SG_STACKS="" SG_STACKS_SOURCE="" SG_STACKS_WARNINGS=""

    _cfg="${SLOPGUARD_CONFIG_FILE:-${root}/.slopguard.json}"

    # ── No file → autodetect, no warning ──────────────────────────────────── #
    if [ ! -f "$_cfg" ]; then
        SG_STACKS="$(detect_stacks "$root")"
        SG_STACKS_SOURCE="auto"
        return 0
    fi

    # ── Parse JSON; failure → warn + autodetect ───────────────────────────── #
    if ! _json="$(jq -e '.' "$_cfg" 2>/dev/null)"; then
        _config_warn "invalid JSON in .slopguard.json — falling back to autodetection"
        SG_STACKS="$(detect_stacks "$root")"
        SG_STACKS_SOURCE="auto"
        return 0
    fi

    # ── Neither key present → autodetect, no warning ─────────────────────── #
    _has_stacks="$(jq -r 'has("stacks")' <<< "$_json")"
    _has_paths="$(jq -r  'has("paths")'  <<< "$_json")"

    if [ "$_has_stacks" = "false" ] && [ "$_has_paths" = "false" ]; then
        SG_STACKS="$(detect_stacks "$root")"
        SG_STACKS_SOURCE="auto"
        return 0
    fi

    _src="auto"

    # ── stacks array ──────────────────────────────────────────────────────── #
    if [ "$_has_stacks" = "true" ]; then
        _stacks_type="$(jq -r '.stacks | type' <<< "$_json")"
        if [ "$_stacks_type" != "array" ]; then
            _config_warn ".slopguard.json: \"stacks\" must be an array — ignored"
        else
            if [ "$(jq '.stacks | length' <<< "$_json")" -eq 0 ]; then
                _config_warn "stacks: [] — no language layer is active"
            fi
            # Capture jq output to variable; feed via here-string to avoid
            # the jaq process-substitution/nested-pipeline stall.
            _stacks_tags="$(jq -r '.stacks[]' <<< "$_json" 2>/dev/null)"
            while IFS= read -r _t; do
                [ -n "$_t" ] || continue
                _explicit_tags="$(_detect_add "$_explicit_tags" "$_t")"
            done <<< "$_stacks_tags"
            _src="file"
        fi
    fi

    # ── paths object ──────────────────────────────────────────────────────── #
    if [ "$_has_paths" = "true" ]; then
        _paths_type="$(jq -r '.paths | type' <<< "$_json")"
        if [ "$_paths_type" != "object" ]; then
            _config_warn ".slopguard.json: \"paths\" must be an object — ignored"
        else
            _paths_keys="$(jq -r '.paths | keys[]' <<< "$_json" 2>/dev/null)"
            while IFS= read -r _p; do
                [ -n "$_p" ] || continue
                if [ ! -d "${root}/${_p}" ]; then
                    _config_warn ".slopguard.json: path \"${_p}\" does not exist — ignored"
                    continue
                fi
                _p_type="$(jq -r --arg k "$_p" '.paths[$k] | type' <<< "$_json")"
                if [ "$_p_type" != "array" ]; then
                    _config_warn ".slopguard.json: \"paths\".\"${_p}\" must be an array of stack tags — ignored"
                    continue
                fi
                _p_tags="$(jq -r --arg k "$_p" '.paths[$k][]' <<< "$_json" 2>/dev/null)"
                while IFS= read -r _t; do
                    [ -n "$_t" ] || continue
                    _paths_tags="$(_detect_add "$_paths_tags" "$_t")"
                done <<< "$_p_tags"
            done <<< "$_paths_keys"
            [ "$_src" = "file" ] || _src="file-paths"
        fi
    fi

    # ── Union → validate → implies → reorder ─────────────────────────────── #
    _all_tags="$(_config_union "$_explicit_tags" "$_paths_tags")"
    _valid_all="$(stacks_all)"
    _validated=""

    # shellcheck disable=SC2086
    for _tag in $_all_tags; do
        if stack_known "$_tag"; then
            _validated="$(_detect_add "$_validated" "$_tag")"
        else
            _config_warn "unknown stack \"${_tag}\" — ignored (valid: ${_valid_all})"
        fi
    done

    # Apply implies (e.g. helm → kubernetes).
    # requires gating is intentionally NOT applied to explicit lists.
    _implied="$(_config_implies "$_validated")"

    # Re-validate implies results (they come from stacks.json; guard stale JSON).
    _final=""
    # shellcheck disable=SC2086
    for _it in $_implied; do
        stack_known "$_it" && _final="$(_detect_add "$_final" "$_it")"
    done

    SG_STACKS="$(_config_order "$_final")"
    SG_STACKS_SOURCE="$_src"
    return 0
}
