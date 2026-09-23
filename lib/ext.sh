#!/usr/bin/env bash
# lib/ext.sh — project-scoped extension mechanism.
#
# (A) Mapping overrides: .slopguard/mapping/<tool>.yaml
# (B) Tool descriptors:  .slopguard/tools/<name>.yaml
#
# Public API:
#   ext_dir            <project_root>
#   ext_load_mapping   <project_root> <tool>
#   ext_override_counts <project_root>
#   ext_tools          <project_root>
#   ext_validate       <file>
#
# Requires: CLAUDE_PLUGIN_ROOT set, jq available.
# Optionally: TOOLS_LOCK (path override for tests).
# Optionally: SLOPGUARD_EXT_DIR (extension root override for tests).

# --------------------------------------------------------------------------- #
# Internal — sha256, YAML, glob helpers
# --------------------------------------------------------------------------- #

# _ext_sha256_file <path>
# SHA-256 of a file.
_ext_sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf 'ext: sha256sum or shasum is required\n' >&2
        return 1
    fi
}

# _ext_yaml_seq_to_json <raw_value>
# Convert a YAML inline sequence or JSON array string to compact JSON array.
# Returns '[]' on empty/missing input. Never exits non-zero.
_ext_yaml_seq_to_json() {
    local val="$1"
    val="${val#"${val%%[! ]*}"}"  # ltrim
    val="${val%"${val##*[! ]}"}"  # rtrim
    [ -n "$val" ] && [ "${val:0:1}" = '[' ] || { printf '[]'; return 0; }
    # Try JSON parse first.
    local out
    out="$(printf '%s' "$val" | jq -c 'if type == "array" then . else error end' 2>/dev/null)" \
        && { printf '%s' "$out"; return 0; }
    # YAML flow sequence: items split by comma.
    local inner="${val:1:${#val}-2}"
    local result='[]' item
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        # Strip YAML quotes.
        local fc="${item:0:1}" lc="${item: -1:1}"
        if [ "$fc" = '"' ] && [ "$lc" = '"' ]; then
            item="${item:1:${#item}-2}"
        elif [ "$fc" = "'" ] && [ "$lc" = "'" ]; then
            item="${item:1:${#item}-2}"
        fi
        result="$(printf '%s' "$result" | jq -c --arg v "$item" '. + [$v]')"
    done <<< "$(printf '%s' "$inner" \
        | awk 'BEGIN{RS=","}{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$0); if($0!="") print}')"
    printf '%s' "$result"
}

# _ext_parse_desc_yaml <file>
# Parse a descriptor YAML file.  Outputs fields separated by ASCII RS (\034).
# Field order: name tier globs stacks proj sha256 args timeout fmt jq
_ext_parse_desc_yaml() {
    awk '
        BEGIN {
            sec=""; name=""; tier=""; globs="[]"; stacks="[]"
            proj="[]"; sha=""; args="[]"; to="8"; fmt="json"; jq=""
        }
        /^---/ || /^#/ { next }
        /^[a-zA-Z]/ {
            if      (/^name:/)    { val=$0; sub(/^name:[[:space:]]*/,   "", val); name=val;  sec="" }
            else if (/^tier:/)    { val=$0; sub(/^tier:[[:space:]]*/,   "", val); tier=val;  sec="" }
            else if (/^match:/)   { sec="match" }
            else if (/^resolve:/) { sec="resolve" }
            else if (/^run:/)     { sec="run" }
            else if (/^parse:/)   { sec="parse" }
            else                  { sec="" }
            next
        }
        sec=="match"   && /^  globs:/       { val=$0; sub(/^[[:space:]]*globs:[[:space:]]*/,      "", val); globs=val }
        sec=="match"   && /^  stacks:/      { val=$0; sub(/^[[:space:]]*stacks:[[:space:]]*/,     "", val); stacks=val }
        sec=="resolve" && /^  project:/     { val=$0; sub(/^[[:space:]]*project:[[:space:]]*/,    "", val); proj=val }
        sec=="resolve" && /^  path_sha256:/ { val=$0; sub(/^[[:space:]]*path_sha256:[[:space:]]*/,"", val); sha=val }
        sec=="run"     && /^  args:/        { val=$0; sub(/^[[:space:]]*args:[[:space:]]*/,       "", val); args=val }
        sec=="run"     && /^  timeout:/     { val=$0; sub(/^[[:space:]]*timeout:[[:space:]]*/,    "", val); to=val }
        sec=="parse"   && /^  format:/      { val=$0; sub(/^[[:space:]]*format:[[:space:]]*/,     "", val); fmt=val }
        sec=="parse"   && /^  jq:/          { val=$0; sub(/^[[:space:]]*jq:[[:space:]]*/,         "", val); jq=val }
        END {
            print name; print tier; print globs; print stacks
            print proj;  print sha;  print args;  print to
            print fmt;   print jq
        }
    ' "$1"
}

# _ext_glob_match <pattern> <path>
# Exit 0 when path matches the fnmatch-style glob pattern (**/ supported).
_ext_glob_match() {
    local pattern="$1" path="$2"
    local regex
    regex="$(printf '%s\n' "$pattern" | awk '{
        gsub(/[.+^$()|\\{}]/, "\\\\&")
        gsub(/\*\*\//, "DSTAR/")
        gsub(/\*\*/, ".*")
        gsub(/\*/, "[^/]*")
        gsub(/\?/, "[^/]")
        gsub(/DSTAR\//, "(.*/)?")
        printf "^%s$\n", $0
    }')"
    printf '%s' "$path" | grep -qE "$regex" 2>/dev/null
}

# _ext_is_pinned_tool <name>
# Exit 0 when name appears in tools.lock.json.
_ext_is_pinned_tool() {
    local lock="${TOOLS_LOCK:-${CLAUDE_PLUGIN_ROOT}/tools/tools.lock.json}"
    [ -f "$lock" ] || return 1
    jq -e --arg n "$1" '.tools[$n] != null' "$lock" >/dev/null 2>&1
}

# _ext_strip_scalar_quotes <value>
# Strip surrounding single or double YAML quotes from a scalar.
_ext_strip_scalar_quotes() {
    local v="$1"
    v="${v//\"/}" ; v="${v//\'/}" ; printf '%s' "$v"
}

# _ext_strip_outer_quotes <value>
# Strip only the outermost quote pair (for jq expressions that contain inner quotes).
_ext_strip_outer_quotes() {
    local v="$1" fc lc
    fc="${v:0:1}" ; lc="${v: -1:1}"
    if [ "$fc" = "'" ] && [ "$lc" = "'" ]; then
        printf '%s' "${v:1:${#v}-2}"
    elif [ "$fc" = '"' ] && [ "$lc" = '"' ]; then
        printf '%s' "${v:1:${#v}-2}"
    else
        printf '%s' "$v"
    fi
}

# _ext_refused_json <name> <status> <resolved>
# Emit a refused NDJSON descriptor line.
_ext_refused_json() {
    jq -n -c \
        --arg name     "$1" \
        --arg status   "$2" \
        --arg resolved "$3" \
        '{name:$name, tier:"", match:{globs:[],stacks:[]},
          run:{args:[],timeout:8}, parse:{format:"",jq:""},
          resolved:$resolved, status:$status}'
}

# --------------------------------------------------------------------------- #
# Internal — mapping YAML parsers
# --------------------------------------------------------------------------- #

# _ext_parse_mapping_full <yaml>
# Emit one NDJSON line per rule with all fields set (empty string for absent).
_ext_parse_mapping_full() {
    local yaml="$1"
    [ -f "$yaml" ] || return 0
    awk '
        BEGIN { in_r=0; rule=""; ap=""; sev=""; cat=""; cw="" }
        /^rules:/ { in_r=1; next }
        !in_r     { next }
        /^  [^ ]/ {
            if (rule != "") {
                printf "{\"rule\":\"%s\",\"ap_id\":\"%s\",\"severity\":\"%s\",\"category\":\"%s\",\"cwe\":\"%s\"}\n",
                    rule, ap, sev, cat, cw
            }
            rule=$1; sub(/:$/,"",rule); gsub(/["'"'"']/,"",rule)
            ap=""; sev=""; cat=""; cw=""
        }
        /^    ap_id:/    { ap  = $2 }
        /^    severity:/ { sev = $2 }
        /^    category:/ { cat = $2 }
        /^    cwe:/      { cw  = $2; gsub(/["'"'"']/,"",cw) }
        END {
            if (rule != "") {
                printf "{\"rule\":\"%s\",\"ap_id\":\"%s\",\"severity\":\"%s\",\"category\":\"%s\",\"cwe\":\"%s\"}\n",
                    rule, ap, sev, cat, cw
            }
        }
    ' "$yaml"
}

# _ext_parse_mapping_partial <yaml>
# Emit NDJSON with only explicitly-set fields (for project override merging).
_ext_parse_mapping_partial() {
    local yaml="$1"
    [ -f "$yaml" ] || return 0
    awk '
        BEGIN { in_r=0; rule=""; ap=""; sev=""; cat=""; cw=""; ap_s=0; sev_s=0; cat_s=0; cw_s=0 }
        function emit() {
            if (rule == "") return
            printf "{\"rule\":\"%s\"", rule
            if (ap_s)  printf ",\"ap_id\":\"%s\"",  ap
            if (sev_s) printf ",\"severity\":\"%s\"", sev
            if (cat_s) printf ",\"category\":\"%s\"", cat
            if (cw_s)  printf ",\"cwe\":\"%s\"",     cw
            printf "}\n"
        }
        /^rules:/ { in_r=1; next }
        !in_r     { next }
        /^  [^ ]/ {
            emit()
            rule=$1; sub(/:$/,"",rule); gsub(/["'"'"']/,"",rule)
            ap=""; sev=""; cat=""; cw=""; ap_s=0; sev_s=0; cat_s=0; cw_s=0
        }
        /^    ap_id:/    { ap  = $2; ap_s=1 }
        /^    severity:/ { sev = $2; sev_s=1 }
        /^    category:/ { cat = $2; cat_s=1 }
        /^    cwe:/      { cw  = $2; gsub(/["'"'"']/,"",cw); cw_s=1 }
        END { emit() }
    ' "$yaml"
}

# _ext_compare_severities <plugin_yaml> <proj_yaml>
# Print "<total_overrides> <severity_downgrades>" by comparing matching rules.
_ext_compare_severities() {
    awk '
        BEGIN { file_n=0; in_r=0; rule=""; sev=""; sev_s=0; total=0; down=0 }
        function rank(s) {
            if (s=="blocker") return 3
            if (s=="error")   return 2
            if (s=="warn")    return 1
            if (s=="info")    return 0
            return -1
        }
        function flush_plugin() {
            if (rule != "" && sev != "") plug[rule] = sev
        }
        function flush_proj() {
            if (rule == "" || !sev_s) return
            if (!(rule in plug)) return
            total++
            if (rank(sev) < rank(plug[rule])) down++
        }
        FNR == 1 {
            file_n++
            if (file_n == 2) {
                flush_plugin()
                in_r=0; rule=""; sev=""; sev_s=0
            }
        }
        /^rules:/ { in_r=1; next }
        !in_r     { next }
        /^  [^ ]/ {
            if (file_n == 1) flush_plugin()
            else             flush_proj()
            rule=$1; sub(/:$/,"",rule); gsub(/["'"'"']/,"",rule)
            sev=""; sev_s=0
        }
        /^    severity:/ { sev=$2; sev_s=1 }
        END {
            if (file_n == 1) flush_plugin()
            else             flush_proj()
            printf "%d %d\n", total, down
        }
    ' "$1" "$2"
}

# --------------------------------------------------------------------------- #
# Internal — descriptor evaluation
# --------------------------------------------------------------------------- #

# _ext_eval_descriptor <file> <project_root>
# Parse, validate, and resolve one descriptor.
# Always exits 0; outputs one NDJSON line with status: ok | absent | refused:<reason>.
_ext_eval_descriptor() {
    local file="$1" project_root="$2"
    local basename="${file##*/}"
    local expect_name="${basename%.yaml}"

    # --- Parse ---
    local raw
    raw="$(_ext_parse_desc_yaml "$file" 2>/dev/null)" || {
        _ext_refused_json "$expect_name" "refused:parse-error" ""; return 0
    }
    local name tier globs_raw stacks_raw proj_raw sha256_raw args_raw timeout_raw fmt jq_raw
    {
        IFS= read -r name; IFS= read -r tier
        IFS= read -r globs_raw; IFS= read -r stacks_raw; IFS= read -r proj_raw
        IFS= read -r sha256_raw; IFS= read -r args_raw; IFS= read -r timeout_raw
        IFS= read -r fmt; IFS= read -r jq_raw
    } <<< "$raw"

    # Strip quotes from scalars.
    name="$(_ext_strip_scalar_quotes "$name")"
    tier="$(_ext_strip_scalar_quotes "$tier")"
    sha256_raw="$(_ext_strip_scalar_quotes "$sha256_raw")"
    timeout_raw="$(_ext_strip_scalar_quotes "$timeout_raw")"
    fmt="$(_ext_strip_scalar_quotes "$fmt")"
    jq_raw="$(_ext_strip_outer_quotes "$jq_raw")"

    # --- Structural validation ---

    [ -n "$name" ] || {
        _ext_refused_json "$expect_name" "refused:missing-name" ""; return 0
    }
    [ "$name" = "$expect_name" ] || {
        _ext_refused_json "$name" "refused:name-mismatch" ""; return 0
    }
    [ "$tier" = "fast" ] || {
        _ext_refused_json "$name" "refused:invalid-tier" ""; return 0
    }

    local args_json; args_json="$(_ext_yaml_seq_to_json "$args_raw")"
    local args_count; args_count="$(printf '%s' "$args_json" | jq 'length' 2>/dev/null || printf '0')"
    [ "${args_count:-0}" -gt 0 ] || {
        _ext_refused_json "$name" "refused:empty-args" ""; return 0
    }

    [ -n "$jq_raw" ] || {
        _ext_refused_json "$name" "refused:missing-jq" ""; return 0
    }

    # --- Pinned-tool collision ---
    if _ext_is_pinned_tool "$name"; then
        _ext_refused_json "$name" "refused:pinned-tool-collision" ""; return 0
    fi

    # --- Resolution check (structural: at least one field present) ---
    local proj_json; proj_json="$(_ext_yaml_seq_to_json "$proj_raw")"
    local has_proj; has_proj="$(printf '%s' "$proj_json" | jq 'length > 0' 2>/dev/null || printf 'false')"
    if [ "$has_proj" != 'true' ] && [ -z "$sha256_raw" ]; then
        _ext_refused_json "$name" "refused:no-resolution" ""; return 0
    fi

    # --- Parse remaining arrays ---
    local globs_json; globs_json="$(_ext_yaml_seq_to_json "$globs_raw")"
    local stacks_json; stacks_json="$(_ext_yaml_seq_to_json "$stacks_raw")"
    local timeout_int="${timeout_raw:-8}"
    case "$timeout_int" in ''|*[!0-9]*) timeout_int=8 ;; esac

    # --- Runtime binary resolution ---
    local resolved="" status="absent"

    # 1. Project-relative paths.
    if [ "$has_proj" = 'true' ]; then
        local path_entry
        local proj_entries; proj_entries="$(printf '%s' "$proj_json" | jq -r '.[]' 2>/dev/null || true)"
        while IFS= read -r path_entry; do
            [ -n "$path_entry" ] || continue
            local candidate="${project_root}/${path_entry}"
            if [ -f "$candidate" ] && [ -x "$candidate" ]; then
                resolved="$candidate"
                status="ok"
                break
            fi
        done <<< "$proj_entries"
    fi

    # 2. PATH binary with sha256 guard.
    if [ -z "$resolved" ] && [ -n "$sha256_raw" ]; then
        if command -v "$name" >/dev/null 2>&1; then
            local path_bin; path_bin="$(command -v "$name")"
            local actual_sha; actual_sha="$(_ext_sha256_file "$path_bin" 2>/dev/null)" || actual_sha=""
            if [ "$actual_sha" = "$sha256_raw" ]; then
                resolved="$path_bin"
                status="ok"
            else
                _ext_refused_json "$name" "refused:sha256-mismatch" ""; return 0
            fi
        fi
        # Binary not on PATH → remains absent (not a refusal).
    fi

    jq -n -c \
        --arg     name     "$name"        \
        --arg     tier     "$tier"        \
        --argjson globs    "$globs_json"  \
        --argjson stacks   "$stacks_json" \
        --argjson args     "$args_json"   \
        --argjson timeout  "$timeout_int" \
        --arg     fmt      "$fmt"         \
        --arg     jq_expr  "$jq_raw"      \
        --arg     resolved "$resolved"    \
        --arg     status   "$status"      \
        '{name:$name, tier:$tier,
          match:{globs:$globs, stacks:$stacks},
          run:{args:$args, timeout:$timeout},
          parse:{format:$fmt, jq:$jq_expr},
          resolved:$resolved, status:$status}'
}

# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #

# ext_dir <project_root>
# Print the extension directory root.
ext_dir() {
    printf '%s' "${SLOPGUARD_EXT_DIR:-${1}/.slopguard}"
}

# ext_load_mapping <project_root> <tool>
# Print merged rule table as NDJSON (one object per line):
#   {"rule":"...","ap_id":"...","severity":"...","category":"...","cwe":"..."}
# Plugin entries first; project patches field-by-field; unknown project rule ids
# are additions.
ext_load_mapping() {
    local project_root="$1" tool="$2"
    local plugin_yaml="${CLAUDE_PLUGIN_ROOT}/rules/mapping/${tool}.yaml"
    local ext_d; ext_d="$(ext_dir "$project_root")"
    local proj_yaml="${ext_d}/mapping/${tool}.yaml"

    # No plugin mapping: use project-only (extension tools have no plugin mapping).
    if [ ! -f "$plugin_yaml" ]; then
        [ -f "$proj_yaml" ] && _ext_parse_mapping_full "$proj_yaml"
        return 0
    fi

    local plugin_nd; plugin_nd="$(_ext_parse_mapping_full "$plugin_yaml")"
    [ -n "$plugin_nd" ] || return 0

    if [ ! -f "$proj_yaml" ]; then
        printf '%s\n' "$plugin_nd"
        return 0
    fi

    local proj_nd; proj_nd="$(_ext_parse_mapping_partial "$proj_yaml")"

    # Merge via jq using temp files (avoids process-substitution / jaq stall).
    local tmp_p tmp_r
    tmp_p="$(mktemp)"
    tmp_r="$(mktemp)"
    printf '%s\n' "$plugin_nd" > "$tmp_p"
    { [ -n "$proj_nd" ] && printf '%s\n' "$proj_nd"; } > "$tmp_r"

    local merged
    merged="$(jq -nc \
        --slurpfile plugin "$tmp_p" \
        --slurpfile proj   "$tmp_r" \
        '
        ($plugin | map({(.rule): .}) | add // {}) as $base |
        ($proj   | map({(.rule): .}) | add // {}) as $over |
        ($base | to_entries | map(
            .key as $k |
            { value: ($base[$k] * ($over[$k] // {})) }
        ) | map(.value)) as $merged |
        ($over | to_entries | map(select($base[.key] == null)) | map(.value)) as $new |
        ($merged + $new)[] |
        {rule: (.rule // ""), ap_id: (.ap_id // ""),
         severity: (.severity // ""), category: (.category // ""), cwe: (.cwe // "")}
        ' 2>/dev/null)"

    rm -f "$tmp_p" "$tmp_r"
    [ -n "$merged" ] && printf '%s\n' "$merged"
}

# ext_override_counts <project_root>
# Print "<total_overrides> <severity_downgrades>" (always two integers).
# Severity rank for downgrade detection: blocker > error > warn > info.
ext_override_counts() {
    local project_root="$1"
    local ext_d; ext_d="$(ext_dir "$project_root")"
    local mapping_dir="${ext_d}/mapping"
    local total=0 downgrades=0

    if [ -d "$mapping_dir" ]; then
        local proj_yaml
        for proj_yaml in "${mapping_dir}"/*.yaml; do
            [ -f "$proj_yaml" ] || continue
            local tool="${proj_yaml##*/}"; tool="${tool%.yaml}"
            local plugin_yaml="${CLAUDE_PLUGIN_ROOT}/rules/mapping/${tool}.yaml"
            [ -f "$plugin_yaml" ] || continue
            local counts; counts="$(_ext_compare_severities "$plugin_yaml" "$proj_yaml")"
            local t d; read -r t d <<< "$counts"
            total=$((total + ${t:-0}))
            downgrades=$((downgrades + ${d:-0}))
        done
    fi

    printf '%d %d' "$total" "$downgrades"
}

# ext_tools <project_root>
# Print one NDJSON object per descriptor file (including refused ones).
# Fields: name, tier, match, run, parse, resolved, status.
ext_tools() {
    local project_root="$1"
    local ext_d; ext_d="$(ext_dir "$project_root")"
    local desc_dir="${ext_d}/tools"
    [ -d "$desc_dir" ] || return 0

    local f
    for f in "${desc_dir}"/*.yaml; do
        [ -f "$f" ] || continue
        _ext_eval_descriptor "$f" "$project_root"
    done
}

# ext_validate <file>
# Exit 0 when the file is structurally valid; print reason to stderr and exit 1
# otherwise.  Works for both descriptor files and mapping override files.
ext_validate() {
    local file="$1"
    [ -f "$file" ] || {
        printf 'ext_validate: file not found: %s\n' "$file" >&2; return 1
    }

    # Detect type: mapping files have a top-level "rules:" key.
    if grep -q '^rules:' "$file" 2>/dev/null; then
        # Mapping validation: must have at least one rule entry.
        local rc; rc="$(awk '/^  [^ ]/{c++} END{print c+0}' "$file")"
        [ "${rc:-0}" -gt 0 ] || {
            printf 'mapping: no rule entries found\n' >&2; return 1
        }
        return 0
    fi

    # Descriptor validation.
    local raw; raw="$(_ext_parse_desc_yaml "$file" 2>/dev/null)" || {
        printf 'descriptor: parse error\n' >&2; return 1
    }

    local name tier globs_raw stacks_raw proj_raw sha256_raw args_raw timeout_raw fmt jq_raw
    {
        IFS= read -r name; IFS= read -r tier
        IFS= read -r globs_raw; IFS= read -r stacks_raw; IFS= read -r proj_raw
        IFS= read -r sha256_raw; IFS= read -r args_raw; IFS= read -r timeout_raw
        IFS= read -r fmt; IFS= read -r jq_raw
    } <<< "$raw"

    name="$(_ext_strip_scalar_quotes "$name")"
    tier="$(_ext_strip_scalar_quotes "$tier")"
    sha256_raw="$(_ext_strip_scalar_quotes "$sha256_raw")"
    jq_raw="$(_ext_strip_outer_quotes "$jq_raw")"

    [ -n "$name" ] || { printf 'descriptor: missing name\n' >&2; return 1; }
    [ "$tier" = "fast" ] || {
        printf 'descriptor: invalid tier: %s\n' "$tier" >&2; return 1
    }

    local args_json; args_json="$(_ext_yaml_seq_to_json "$args_raw")"
    local args_count; args_count="$(printf '%s' "$args_json" | jq 'length' 2>/dev/null || printf '0')"
    [ "${args_count:-0}" -gt 0 ] || {
        printf 'descriptor: empty or missing run.args\n' >&2; return 1
    }

    [ -n "$jq_raw" ] || { printf 'descriptor: missing parse.jq\n' >&2; return 1; }

    local proj_json; proj_json="$(_ext_yaml_seq_to_json "$proj_raw")"
    local has_proj; has_proj="$(printf '%s' "$proj_json" | jq 'length > 0' 2>/dev/null || printf 'false')"
    if [ "$has_proj" != 'true' ] && [ -z "$sha256_raw" ]; then
        printf 'descriptor: no resolution: set resolve.project or resolve.path_sha256\n' >&2
        return 1
    fi

    return 0
}
