#!/usr/bin/env bash
# lib/detect.sh — data-driven stack detection from rules/stacks.json.

# _detect_add <list> <tag>
# Returns <list> with <tag> appended, silently deduplicating.
_detect_add() {
    case " $1 " in *" $2 "*) printf '%s' "$1" ;; *) printf '%s%s' "${1:+$1 }" "$2" ;; esac
}

# detect_stacks [<root>]
# Prints space-separated detected stack tags to stdout in stacks.json key order
# and returns 0.  Missing or unreadable stacks.json → prints nothing, returns 0.
detect_stacks() {
    local root="${1:-.}"
    : "${SLOPGUARD_STACKS_JSON:=${CLAUDE_PLUGIN_ROOT}/rules/stacks.json}"
    local _sf="$SLOPGUARD_STACKS_JSON"

    [ -f "$_sf" ] || { printf '\n'; return 0; }

    # One jq call: emit metadata and anchor-check lines for every tag.
    # Line types:
    #   order|<tag>                     — tag in stacks.json key order
    #   req|<tag>|<requires>            — requires gate (empty when absent)
    #   imp|<tag>|<implied>             — one entry per implied tag
    #   file|<tag>|<filename>           — exact basename at root
    #   glob|<tag>|<pattern>            — root-relative shell glob
    #   dir|<tag>|<dirpath>             — directory at root
    #   manifest|<tag>|<file>|<substr>  — literal substring in manifest file
    local _jq_out
    _jq_out=$(jq -r '
        . as $d | keys_unsorted[] as $t | $d[$t] as $e |
        (
            "order|\($t)",
            "req|\($t)|\($e.requires // "")",
            (($e.implies // [])[]         | "imp|\($t)|\(.)"),
            (($e.anchors.files  // [])[]  | "file|\($t)|\(.)"),
            (($e.anchors.globs  // [])[]  | "glob|\($t)|\(.)"),
            (($e.anchors.dirs   // [])[]  | "dir|\($t)|\(.)"),
            (($e.anchors.manifest // {})
             | to_entries[]
             | .key as $f | .value[]
             | "manifest|\($t)|\($f)|\(.)")
        )
    ' "$_sf" 2>/dev/null) || { printf '\n'; return 0; }

    local _type _tag _a1 _a2 _f _fname
    local -a _tag_order=() _req_list=() _imp_list=()
    local _raw=""

    while IFS='|' read -r _type _tag _a1 _a2; do
        case "$_type" in
            order)
                _tag_order+=("$_tag")
                ;;
            req)
                [ -n "$_a1" ] && _req_list+=("${_tag}:${_a1}")
                ;;
            imp)
                _imp_list+=("${_tag}|${_a1}")
                ;;
            file)
                [ -f "$root/$_a1" ] && _raw="$(_detect_add "$_raw" "$_tag")"
                ;;
            glob)
                case "$_a1" in
                    \*\*/*)
                        # Recursive glob: find files matching the name pattern.
                        _fname="${_a1#\*\*/}"
                        find "$root" -maxdepth 5 -name "$_fname" -type f 2>/dev/null \
                            | grep -q . && _raw="$(_detect_add "$_raw" "$_tag")"
                        ;;
                    *)
                        # Root-level glob: intentional unquoted expansion.
                        # shellcheck disable=SC2086
                        for _f in "$root"/$_a1; do
                            [ -f "$_f" ] && { _raw="$(_detect_add "$_raw" "$_tag")"; break; }
                        done
                        ;;
                esac
                ;;
            dir)
                [ -d "$root/$_a1" ] && _raw="$(_detect_add "$_raw" "$_tag")"
                ;;
            manifest)
                # _a2 is the literal substring (may include surrounding quotes).
                grep -qF "$_a2" "$root/$_a1" 2>/dev/null \
                    && _raw="$(_detect_add "$_raw" "$_tag")"
                ;;
        esac
    done <<< "$_jq_out"

    # Phase 2: requires gating — keep a tag only when its required tag was
    # also independently detected via its own anchors.
    local _gated="" _req _rentry
    for _tag in "${_tag_order[@]}"; do
        case " $_raw " in *" $_tag "*) ;; *) continue ;; esac
        _req=""
        for _rentry in "${_req_list[@]}"; do
            case "$_rentry" in
                "${_tag}:"*) _req="${_rentry#*:}"; break ;;
            esac
        done
        if [ -n "$_req" ]; then
            case " $_raw " in *" $_req "*) ;; *) continue ;; esac
        fi
        _gated="$(_detect_add "$_gated" "$_tag")"
    done

    # Phase 3: expand implies transitively (bounded to 20 iterations).
    local _stacks="$_gated" _prev _entry _fromtag _imptag _i=0
    while [ "$_i" -lt 20 ]; do
        _prev="$_stacks"
        for _entry in "${_imp_list[@]}"; do
            _fromtag="${_entry%%|*}"
            _imptag="${_entry##*|}"
            case " $_stacks " in
                *" $_fromtag "*) _stacks="$(_detect_add "$_stacks" "$_imptag")" ;;
            esac
        done
        [ "$_stacks" = "$_prev" ] && break
        _i=$((_i + 1))
    done

    printf '%s\n' "$_stacks"
}

# stacks_all
# Prints every known stack tag, space-separated, sorted alphabetically.
# Missing stacks.json → prints nothing and returns 0.
stacks_all() {
    : "${SLOPGUARD_STACKS_JSON:=${CLAUDE_PLUGIN_ROOT}/rules/stacks.json}"
    [ -f "$SLOPGUARD_STACKS_JSON" ] || return 0
    jq -r 'keys | join(" ")' "$SLOPGUARD_STACKS_JSON" 2>/dev/null || true
}

# stack_known <tag>
# Exits 0 if <tag> is a known stack, 1 otherwise.  No output.
stack_known() {
    : "${SLOPGUARD_STACKS_JSON:=${CLAUDE_PLUGIN_ROOT}/rules/stacks.json}"
    [ -f "$SLOPGUARD_STACKS_JSON" ] || return 1
    jq -e --arg t "$1" 'has($t)' "$SLOPGUARD_STACKS_JSON" > /dev/null 2>&1
}

# stack_tier <tag>
# Prints 1 or 2; exits 1 and produces no output for an unknown tag.
stack_tier() {
    : "${SLOPGUARD_STACKS_JSON:=${CLAUDE_PLUGIN_ROOT}/rules/stacks.json}"
    [ -f "$SLOPGUARD_STACKS_JSON" ] || return 1
    local _tier
    _tier=$(jq -re --arg t "$1" \
        'if has($t) then .[$t].tier | tostring else error end' \
        "$SLOPGUARD_STACKS_JSON" 2>/dev/null) || return 1
    printf '%s\n' "$_tier"
}
