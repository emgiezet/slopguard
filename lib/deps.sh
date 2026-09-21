#!/usr/bin/env bash
# lib/deps.sh — dependency freshness checking for slopguard deps-check.
#
# Entry point: deps_check_main [--json] [<root>]
#
# Network: deps_fetch is the ONLY function in this file that calls the network.
# Offline testing: set SLOPGUARD_FETCH_CMD to a script that echoes fixture data
# for a given URL (first positional argument).
#
# jq/jaq quirk (hit twice in this codebase): capture jq output into a variable,
# then feed it to loops via here-string (<<< "$var").  Never use < <(jq ...).

# --------------------------------------------------------------------------- #
# Network
# --------------------------------------------------------------------------- #

# deps_fetch <url>
# The ONLY network call.  Honour SLOPGUARD_FETCH_CMD for offline tests.
# Returns non-zero on any failure; callers degrade gracefully.
deps_fetch() {
    if [ -n "${SLOPGUARD_FETCH_CMD:-}" ]; then
        $SLOPGUARD_FETCH_CMD "$1"
    else
        curl -fsSL --max-time 5 "$1"
    fi
}

# --------------------------------------------------------------------------- #
# Version helpers
# --------------------------------------------------------------------------- #

# _deps_strip_prefix <v>
# Remove leading version-constraint characters (v, ^, ~>, ~, >=, >, <=, <, =)
# and any resulting leading spaces.  Loops so ">= v1.2" → "1.2".
_deps_strip_prefix() {
    local v="$1"
    local prev=""
    while [ "$v" != "$prev" ]; do
        prev="$v"
        case "$v" in
            'v'*)  v="${v#v}" ;;
            '^'*)  v="${v#^}" ;;
            '~>'*) v="${v#\~>}" ;;
            '~'*)  v="${v#\~}" ;;
            '>='*) v="${v#>=}" ;;
            '<='*) v="${v#<=}" ;;
            '>'*)  v="${v#>}" ;;
            '<'*)  v="${v#<}" ;;
            '='*)  v="${v#=}" ;;
            ' '*)  v="${v# }" ;;
        esac
    done
    printf '%s' "$v"
}

# _deps_is_version <v>
# Returns 0 when v looks like a parseable version (starts with a digit after
# stripping any prefix).  Used by deps_verdict to detect junk input.
_deps_is_version() {
    local stripped
    stripped="$(_deps_strip_prefix "$1")"
    case "$stripped" in [0-9]*) return 0 ;; *) return 1 ;; esac
}

# deps_version_cmp <a> <b>
# Component-wise numeric comparison.  Tolerates leading v/^/~>/~/>=.
# Prerelease suffix (-rc1, -beta.2) sorts BELOW the same version without it:
#   1.0.0-rc1 < 1.0.0 < 1.0.1
# Prints -1, 0, or 1.  Never fails — prints 0 on junk input so callers can
# treat the verdict as unknown.
deps_version_cmp() {
    local a b
    a="$(_deps_strip_prefix "$1")"
    b="$(_deps_strip_prefix "$2")"

    # Split prerelease suffix at the first '-'
    local a_pre="" b_pre=""
    case "$a" in *-*) a_pre="${a#*-}"; a="${a%%-*}" ;; esac
    case "$b" in *-*) b_pre="${b#*-}"; b="${b%%-*}" ;; esac

    # Split on '.' into arrays; capture into variable first (jaq workaround)
    local -a a_arr b_arr
    IFS='.' read -ra a_arr <<< "$a"
    IFS='.' read -ra b_arr <<< "$b"

    local max_i="${#a_arr[@]}"
    [ "${#b_arr[@]}" -gt "$max_i" ] && max_i="${#b_arr[@]}"

    local i ai bi
    for (( i=0; i<max_i; i++ )); do
        ai="${a_arr[$i]:-0}"
        bi="${b_arr[$i]:-0}"
        # Non-numeric component — treat as equal (junk-input safety)
        [[ "$ai" =~ ^[0-9]+$ ]] || { printf '%s' '0'; return 0; }
        [[ "$bi" =~ ^[0-9]+$ ]] || { printf '%s' '0'; return 0; }
        if (( ai < bi )); then printf '%s' '-1'; return 0; fi
        if (( ai > bi )); then printf '%s' '1';  return 0; fi
    done

    # Numeric parts equal — apply prerelease ordering:
    # release > prerelease (1.0.0 > 1.0.0-rc1)
    if   [ -z "$a_pre" ] && [ -n "$b_pre" ]; then printf '%s' '1';  return 0
    elif [ -n "$a_pre" ] && [ -z "$b_pre" ]; then printf '%s' '-1'; return 0
    fi
    printf '%s' '0'
}

# deps_age_days <iso8601>
# Whole days elapsed since the given ISO-8601 timestamp.
# Tries GNU date (-d) first, then BSD date (-j -f), then falls back to -1.
deps_age_days() {
    local ts="$1"
    local now epoch
    now="$(date +%s 2>/dev/null)" || { printf '%s' '-1'; return 0; }

    # GNU date accepts ISO-8601 directly; strip trailing Z for wider compat.
    if epoch="$(date -d "${ts%Z}" +%s 2>/dev/null)"; then
        :
    # BSD date: strip sub-second fraction (.000) so the format matches exactly.
    elif epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S' "${ts%%.*}" +%s 2>/dev/null)"; then
        :
    else
        printf '%s' '-1'; return 0
    fi

    printf '%s' "$(( (now - epoch) / 86400 ))"
}

# deps_verdict <pinned> <latest> <age_days> <cooldown_days>
# Prints one of: ok | minor-behind | major-behind | too-fresh | unknown
#
# Precedence:
#   1. unknown  — either version string cannot be parsed
#   2. too-fresh — latest stable is younger than the cooldown window
#      (outranks being behind: recommending a 3-hour-old release is riskier)
#   3. major-behind / minor-behind / ok — based on version comparison
deps_verdict() {
    local pinned="$1" latest="$2" age_days="$3" cooldown_days="$4"

    if ! _deps_is_version "$pinned" || ! _deps_is_version "$latest"; then
        printf '%s' 'unknown'; return 0
    fi

    # too-fresh: only when age is a known non-negative integer
    if [[ "$age_days" =~ ^[0-9]+$ ]] && [[ "$cooldown_days" =~ ^[0-9]+$ ]]; then
        if (( age_days < cooldown_days )); then
            printf '%s' 'too-fresh'; return 0
        fi
    fi

    local cmp
    cmp="$(deps_version_cmp "$pinned" "$latest")"
    case "$cmp" in
        '-1')
            # Pinned is behind; determine major vs minor.
            local pm lm
            pm="$(_deps_strip_prefix "$pinned")"
            lm="$(_deps_strip_prefix "$latest")"
            pm="${pm%%.*}"; pm="${pm%%-*}"   # major of pinned (strip pre-release)
            lm="${lm%%.*}"; lm="${lm%%-*}"   # major of latest
            if [[ "$pm" =~ ^[0-9]+$ ]] && [[ "$lm" =~ ^[0-9]+$ ]] && (( pm < lm )); then
                printf '%s' 'major-behind'
            else
                printf '%s' 'minor-behind'
            fi
            ;;
        '0'|'1')
            printf '%s' 'ok'
            ;;
        *)
            printf '%s' 'unknown'
            ;;
    esac
}

# --------------------------------------------------------------------------- #
# Manifest parsers
# Each prints "package|version" pairs, one per line.  Never aborts on parse
# errors — silently skips unparseable lines.
# --------------------------------------------------------------------------- #

# _deps_parse_npm <package.json>
_deps_parse_npm() {
    local f="$1"
    local out
    out="$(jq -r '
        [.dependencies // {}, .devDependencies // {}]
        | add // {}
        | to_entries[]
        | "\(.key)|\(.value)"
    ' "$f" 2>/dev/null)" || return 0
    [ -n "$out" ] && printf '%s\n' "$out"
}

# _deps_parse_packagist <composer.json>
# Skips the PHP platform requirement and PHP extensions (ext-*).
_deps_parse_packagist() {
    local f="$1"
    local out
    out="$(jq -r '
        [.require // {}, ."require-dev" // {}]
        | add // {}
        | to_entries[]
        | select(.key | test("^(php$|ext-)"; "i") | not)
        | "\(.key)|\(.value)"
    ' "$f" 2>/dev/null)" || return 0
    [ -n "$out" ] && printf '%s\n' "$out"
}

# _deps_parse_go <go.mod>
# Matches tab-indented "module v1.2.3" require lines (both block and inline).
# Strips "// indirect" and similar trailing comments via the third read field.
_deps_parse_go() {
    local f="$1"
    local out
    out="$(grep -E $'^\t[^[:space:]]+[[:space:]]+v[0-9]' "$f" 2>/dev/null)" || return 0
    [ -z "$out" ] && return 0
    while read -r pkg ver _; do
        [ -n "$pkg" ] && [ -n "$ver" ] && printf '%s|%s\n' "$pkg" "$ver"
    done <<< "$out"
}

# _deps_parse_gemfile <Gemfile>
# Handles: gem 'name', '~> 1.0'  and  gem "name", ">= 2"
# Gems declared without a version constraint emit version "*" (→ unknown verdict).
_deps_parse_gemfile() {
    local f="$1"
    local out
    out="$(grep -E '^gem[[:space:]]' "$f" 2>/dev/null)" || return 0
    [ -z "$out" ] && return 0
    while IFS= read -r line; do
        # Extract gem name: first quoted argument
        local name
        name="$(printf '%s' "$line" | sed -nE "s/^gem[[:space:]]+['\"]([^'\"]+)['\"].*/\1/p")"
        [ -z "$name" ] && continue
        # Extract version: second quoted argument (may be absent)
        local ver
        ver="$(printf '%s' "$line" | sed -nE "s/^gem[[:space:]]+['\"][^'\"]+['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p")"
        printf '%s|%s\n' "$name" "${ver:-*}"
    done <<< "$out"
}

# _deps_parse_csproj <*.csproj>
# Matches <PackageReference Include="Foo" Version="1.0" /> (attribute order
# may vary; grep handles both orderings).
_deps_parse_csproj() {
    local f="$1"
    local out
    out="$(grep -i 'PackageReference' "$f" 2>/dev/null)" || return 0
    [ -z "$out" ] && return 0
    while IFS= read -r line; do
        local name ver
        name="$(printf '%s' "$line" | sed -nE 's/.*[Ii]nclude="([^"]+)".*/\1/p')"
        ver="$(printf '%s'  "$line" | sed -nE 's/.*[Vv]ersion="([^"]+)".*/\1/p')"
        [ -n "$name" ] && printf '%s|%s\n' "$name" "${ver:-*}"
    done <<< "$out"
}

# _deps_parse_manifest <ecosystem> <file>
# Dispatches to the correct parser.  Returns 1 for unsupported ecosystems.
_deps_parse_manifest() {
    local eco="$1" f="$2"
    case "$eco" in
        npm)       _deps_parse_npm       "$f" ;;
        packagist) _deps_parse_packagist "$f" ;;
        go)        _deps_parse_go        "$f" ;;
        rubygems)  _deps_parse_gemfile   "$f" ;;
        nuget)     _deps_parse_csproj    "$f" ;;
        *)         return 1 ;;
    esac
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

# deps_check_main [--json] [<root>]
# Read every ecosystem in registries.json, parse manifests found under <root>,
# fetch registry info for each declared dependency, and report verdicts.
deps_check_main() {
    local do_json=0 root="."
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) do_json=1; shift ;;
            -*)
                printf 'slopguard deps-check: unknown flag: %s\n' "$1" >&2
                return 1
                ;;
            *)
                root="$1"; shift
                ;;
        esac
    done
    # Strip trailing slash for consistent glob construction.
    root="${root%/}"

    # ── Network gate ──────────────────────────────────────────────────────── #
    if [ "${CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK:-}" != "true" ]; then
        if [ "$do_json" -eq 0 ]; then
            printf 'deps-check: freshness checking requires CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK=true; skipping.\n'
        fi
        return 0
    fi

    # ── Mode ──────────────────────────────────────────────────────────────── #
    local mode="${CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS:-warn}"
    [ "$mode" = "off" ] && return 0

    local cooldown="${CLAUDE_PLUGIN_OPTION_DEPENDENCY_COOLDOWN_DAYS:-3}"
    [[ "$cooldown" =~ ^[0-9]+$ ]] || cooldown=3

    # ── Registries file ───────────────────────────────────────────────────── #
    local reg_file="${SLOPGUARD_REGISTRIES_JSON:-${CLAUDE_PLUGIN_ROOT}/rules/registries.json}"
    if [ ! -f "$reg_file" ]; then
        printf 'deps-check: registries file not found: %s\n' "$reg_file" >&2
        return 0
    fi

    local ecosystems
    ecosystems="$(jq -r 'keys[]' "$reg_file" 2>/dev/null)" || {
        printf 'deps-check: failed to parse registries.json\n' >&2
        return 0
    }

    # ── Per-ecosystem loop ────────────────────────────────────────────────── #
    local rows_json="[]"
    local count_ok=0 count_minor=0 count_major=0 count_fresh=0 count_unknown=0

    while IFS= read -r eco; do
        [ -z "$eco" ] && continue

        # Get manifests list for this ecosystem (one pattern per line).
        local manifests_json
        manifests_json="$(jq -r --arg e "$eco" '.[$e].manifests[]' "$reg_file" 2>/dev/null)" \
            || continue
        [ -z "$manifests_json" ] && continue

        # Check whether any manifest exists under <root>.
        local has_manifest=0
        while IFS= read -r mpat; do
            [ -z "$mpat" ] && continue
            for f in "$root"/$mpat; do
                [ -f "$f" ] && { has_manifest=1; break 2; }
            done
        done <<< "$manifests_json"
        [ "$has_manifest" -eq 0 ] && continue

        # Skip ecosystems whose manifests cannot be safely parsed in bash.
        case "$eco" in
            pypi)
                [ "$do_json" -eq 0 ] && \
                    printf 'skipped: %s (TOML format requires a dedicated parser)\n' "$eco"
                continue
                ;;
            maven)
                [ "$do_json" -eq 0 ] && \
                    printf 'skipped: %s (multi-line XML and compound artifact key require a dedicated parser)\n' "$eco"
                continue
                ;;
        esac

        # Fetch registry config for this ecosystem.
        local url_pat latest_jq published_jq
        url_pat="$(jq -r --arg e "$eco" '.[$e].url'          "$reg_file" 2>/dev/null)"
        latest_jq="$(jq -r --arg e "$eco" '.[$e].latest_jq'  "$reg_file" 2>/dev/null)"
        published_jq="$(jq -r --arg e "$eco" '.[$e].published_jq' "$reg_file" 2>/dev/null)"

        # Parse all manifests for this ecosystem into "pkg|version" pairs.
        local all_deps=""
        while IFS= read -r mpat; do
            [ -z "$mpat" ] && continue
            for f in "$root"/$mpat; do
                [ -f "$f" ] || continue
                local parsed
                parsed="$(_deps_parse_manifest "$eco" "$f" 2>/dev/null)" || continue
                [ -n "$parsed" ] && all_deps="${all_deps}${parsed}"$'\n'
            done
        done <<< "$manifests_json"
        [ -z "$all_deps" ] && continue

        # Process each dependency; deduplicate by package name (first wins).
        local seen_pkgs=""
        while IFS='|' read -r pkg pinned; do
            [ -z "$pkg" ] && continue
            case " $seen_pkgs " in *" $pkg "*) continue ;; esac
            seen_pkgs="$seen_pkgs $pkg"

            # Construct registry URL and fetch.
            local url
            url="${url_pat//\{package\}/$pkg}"
            local reg_data latest age_days verdict
            age_days='-1'
            latest=""

            if ! reg_data="$(deps_fetch "$url" 2>/dev/null)"; then
                # Fetch failure → unknown row; run continues.
                verdict="unknown"
                count_unknown=$(( count_unknown + 1 ))
            else
                # Capture jq output to variable before any loop (jaq workaround).
                local jq_latest
                jq_latest="$(printf '%s' "$reg_data" | jq -r "$latest_jq" 2>/dev/null)" \
                    || jq_latest=""
                [ "$jq_latest" = "null" ] && jq_latest=""
                latest="$jq_latest"

                if [ -z "$latest" ]; then
                    verdict="unknown"
                    count_unknown=$(( count_unknown + 1 ))
                else
                    # Get publication timestamp for the resolved latest version.
                    local jq_pub
                    jq_pub="$(printf '%s' "$reg_data" | \
                        jq -r --arg v "$latest" "$published_jq" 2>/dev/null)" \
                        || jq_pub=""
                    [ "$jq_pub" = "null" ] && jq_pub=""

                    if [ -n "$jq_pub" ]; then
                        age_days="$(deps_age_days "$jq_pub")"
                    fi

                    verdict="$(deps_verdict "$pinned" "$latest" "$age_days" "$cooldown")"

                    case "$verdict" in
                        ok)           count_ok=$(( count_ok + 1 )) ;;
                        too-fresh)    count_fresh=$(( count_fresh + 1 )) ;;
                        major-behind) count_major=$(( count_major + 1 )) ;;
                        minor-behind) count_minor=$(( count_minor + 1 )) ;;
                        *)            count_unknown=$(( count_unknown + 1 )) ;;
                    esac
                fi
            fi

            # Append row to JSON array.
            local row
            row="$(jq -n \
                --arg eco     "$eco"     \
                --arg pkg     "$pkg"     \
                --arg pinned  "$pinned"  \
                --arg latest  "$latest"  \
                --arg verdict "$verdict" \
                --argjson age "$age_days" \
                '{ecosystem:$eco,package:$pkg,pinned:$pinned,latest:$latest,verdict:$verdict,age_days:$age}')"
            rows_json="$(jq -n \
                --argjson arr "$rows_json" \
                --argjson row "$row" \
                '$arr + [$row]')"

        done <<< "$all_deps"

    done <<< "$ecosystems"

    # ── Output ────────────────────────────────────────────────────────────── #
    # Exit status is independent of the output format: CI typically consumes
    # --json, and swallowing the failure there would make error mode useless.
    local rc=0
    if [ "$mode" = "error" ] && [ "$count_major" -gt 0 ]; then
        rc=1
    fi

    if [ "$do_json" -eq 1 ]; then
        printf '%s\n' "$rows_json"
        return "$rc"
    fi

    local row_count
    row_count="$(jq 'length' <<< "$rows_json")"

    if [ "${row_count:-0}" -gt 0 ]; then
        printf '%-14s  %-38s  %-15s  %-15s  %-15s  %s\n' \
            'ecosystem' 'package' 'pinned' 'latest' 'verdict' 'age'
        printf '%0.s-' {1..112}; printf '\n'

        local table
        table="$(jq -r '
            .[] | [.ecosystem, .package, .pinned, .latest, .verdict, (.age_days | tostring)]
            | join("|")
        ' <<< "$rows_json")"

        while IFS='|' read -r t_eco t_pkg t_pin t_lat t_verd t_age; do
            local age_str
            if [ "$t_age" = "-1" ]; then
                age_str="unknown"
            else
                age_str="${t_age} days"
            fi
            printf '%-14s  %-38s  %-15s  %-15s  %-15s  %s\n' \
                "$t_eco" "$t_pkg" "$t_pin" "$t_lat" "$t_verd" "$age_str"
        done <<< "$table"
        printf '\n'
    fi

    local total_behind=$(( count_minor + count_major ))
    printf 'Summary: %d ok, %d behind (%d major), %d too-fresh, %d unknown\n' \
        "$count_ok" "$total_behind" "$count_major" "$count_fresh" "$count_unknown"

    return "$rc"
}
