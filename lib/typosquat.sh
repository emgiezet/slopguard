#!/usr/bin/env bash
# lib/typosquat.sh — network-free package-name signals for dependency prompts.

typosquat_hint() {
    local command="$1" ecosystem="" package="" start=0 index word base list result
    local -a words
    read -r -a words <<< "$command"
    [ "${#words[@]}" -ge 3 ] || return 0

    case "${words[0]} ${words[1]}" in
        'npm add'|'npm install'|'npm i'|'pnpm add'|'pnpm install'|'pnpm i'|'yarn add'|'yarn install'|'yarn i'|'bun add'|'bun install'|'bun i')
            ecosystem="node"; start=2 ;;
        'composer require') ecosystem="php"; start=2 ;;
        'pip install'|'uv add'|'poetry add') ecosystem="python"; start=2 ;;
        'go get'|'go install') ecosystem="go"; start=2 ;;
        *) return 0 ;;
    esac

    index="$start"
    while [ "$index" -lt "${#words[@]}" ]; do
        word="${words[$index]}"
        case "$word" in -*) index=$((index + 1)) ;; *) package="$word"; break ;; esac
    done
    [ -n "$package" ] || return 0

    package="${package#\"}"; package="${package%\"}"
    package="${package#\'}"; package="${package%\'}"
    case "$ecosystem" in
        node) package="${package%%@*}"; [ -n "$package" ] || package="$word" ;;
        python) package="${package%%[\[<>=!~]*}" ;;
        go) package="${package%%@*}" ;;
    esac

    list="${PLUGIN_ROOT}/rules/policies/popular-packages/${ecosystem}.txt"
    [ -f "$list" ] || return 0
    grep -Fqx -- "$package" "$list" && return 0

    case "$package" in
        *-js|*-dev|*-utils)
            base="${package%-js}"; base="${base%-dev}"; base="${base%-utils}"
            if grep -Fqx -- "$base" "$list"; then
                printf "; package name adds a common suffix to popular '%s'" "$base"
                return 0
            fi ;;
    esac

    result="$(awk -v candidate="$package" '
        function distance(a, b,    i,j,cost,left,up,diag,minv) {
            for (j = 0; j <= length(b); j++) previous[j] = j
            for (i = 1; i <= length(a); i++) {
                current[0] = i
                for (j = 1; j <= length(b); j++) {
                    cost = substr(a,i,1) == substr(b,j,1) ? 0 : 1
                    left = current[j-1] + 1
                    up = previous[j] + 1
                    diag = previous[j-1] + cost
                    minv = left < up ? left : up
                    current[j] = minv < diag ? minv : diag
                }
                for (j = 0; j <= length(b); j++) previous[j] = current[j]
            }
            return previous[length(b)]
        }
        NF && count++ < 200 {
            value = distance(tolower(candidate), tolower($0))
            if (best == "" || value < best) { best = value; nearest = $0 }
        }
        END { if (best != "" && best <= 2) printf "; package name is edit distance %d from popular %s", best, nearest }
    ' "$list")"
    printf '%s' "$result"
}
