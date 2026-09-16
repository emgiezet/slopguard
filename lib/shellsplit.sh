#!/usr/bin/env bash
# lib/shellsplit.sh — emit commands and unquoted control operators, one per line.

_shellsplit_emit() {
    [[ "$1" =~ [^[:space:]] ]] && printf '%s\n' "$1"
}

shellsplit() {
    local input="$1" current="" quote="" escaped=0
    local i=0 length="${#1}" char next operator

    while [ "$i" -lt "$length" ]; do
        char="${input:i:1}"
        next="${input:i:2}"

        if [ "$escaped" -eq 1 ]; then
            current+="$char"
            escaped=0
            i=$((i + 1))
            continue
        fi
        if [ "$char" = '\' ] && [ "$quote" != "'" ]; then
            current+="$char"
            escaped=1
            i=$((i + 1))
            continue
        fi
        if [ "$char" = "'" ]; then
            current+="$char"
            if [ -z "$quote" ]; then quote="'"; elif [ "$quote" = "'" ]; then quote=""; fi
            i=$((i + 1))
            continue
        fi
        if [ "$char" = '"' ]; then
            current+="$char"
            if [ -z "$quote" ]; then quote='"'; elif [ "$quote" = '"' ]; then quote=""; fi
            i=$((i + 1))
            continue
        fi

        if [ "$quote" != "'" ] && [ "$char" = '`' ]; then
            _shellsplit_emit "$current"
            current=""
            local tick_body="" tick_escaped=0
            i=$((i + 1))
            while [ "$i" -lt "$length" ]; do
                char="${input:i:1}"
                if [ "$char" = '`' ] && [ "$tick_escaped" -eq 0 ]; then break; fi
                tick_body+="$char"
                if [ "$char" = '\' ] && [ "$tick_escaped" -eq 0 ]; then
                    tick_escaped=1
                else
                    tick_escaped=0
                fi
                i=$((i + 1))
            done
            shellsplit "$tick_body"
            i=$((i + 1))
            continue
        fi

        if [ "$quote" != "'" ] && [ "$next" = '$(' ]; then
            _shellsplit_emit "$current"
            current=""
            local body="" inner_quote="" inner_escaped=0 depth=1
            i=$((i + 2))
            while [ "$i" -lt "$length" ] && [ "$depth" -gt 0 ]; do
                char="${input:i:1}"
                next="${input:i:2}"
                if [ "$inner_escaped" -eq 1 ]; then
                    body+="$char"
                    inner_escaped=0
                elif [ "$char" = '\' ] && [ "$inner_quote" != "'" ]; then
                    body+="$char"
                    inner_escaped=1
                elif [ "$char" = "'" ] || [ "$char" = '"' ]; then
                    body+="$char"
                    if [ -z "$inner_quote" ]; then
                        inner_quote="$char"
                    elif [ "$inner_quote" = "$char" ]; then
                        inner_quote=""
                    fi
                elif [ -z "$inner_quote" ] && [ "$next" = '$(' ]; then
                    body+='$('
                    depth=$((depth + 1))
                    i=$((i + 1))
                elif [ -z "$inner_quote" ] && [ "$char" = ')' ]; then
                    depth=$((depth - 1))
                    [ "$depth" -gt 0 ] && body+="$char"
                else
                    body+="$char"
                fi
                i=$((i + 1))
            done
            shellsplit "$body"
            continue
        fi

        operator=""
        if [ -z "$quote" ]; then
            case "$next" in '&&'|'||') operator="$next" ;; esac
            if [ -z "$operator" ]; then
                case "$char" in
                    ';'|'|'|'('|')') operator="$char" ;;
                    $'\n'|$'\r') operator=';' ;;
                esac
            fi
        fi
        if [ -n "$operator" ]; then
            _shellsplit_emit "$current"
            current=""
            printf '%s\n' "$operator"
            i=$((i + ${#operator}))
            continue
        fi

        current+="$char"
        i=$((i + 1))
    done

    _shellsplit_emit "$current"
}
