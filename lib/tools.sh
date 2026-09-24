#!/usr/bin/env bash
# lib/tools.sh — tool resolution and installation for slop-guard.
#
# Sources (§9.1, tool_source=project-first):
#   1. Project binary: vendor/bin, node_modules/.bin, .venv/bin, go tool -n
#   2. Plugin binary:  ${CLAUDE_PLUGIN_DATA}/tools/<name>/current/<name>
#                      accepted only when --version equals the lockfile version
#   3. PATH binary — only when --version equals the lockfile version
#
# Requires: jq (or a compatible implementation), sha256sum or shasum.
# No flock: file locking uses mkdir (POSIX, macOS-safe per D1).

# --------------------------------------------------------------------------- #
# sha256 helper
# --------------------------------------------------------------------------- #

_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf 'slopguard: sha256sum or shasum is required\n' >&2
        return 1
    fi
}

# --------------------------------------------------------------------------- #
# atomic symlink helper
# --------------------------------------------------------------------------- #

# _mv_atomic_symlink <src> <dst>
# Replaces dst atomically even when dst is a symlink pointing to a directory.
# GNU mv: -T prevents following the destination symlink.
# BSD/macOS mv: -h prevents following the destination symlink.
_mv_atomic_symlink() {
    mv -fT "$1" "$2" 2>/dev/null || mv -fh "$1" "$2"
}

# --------------------------------------------------------------------------- #
# platform detection
# --------------------------------------------------------------------------- #

# detect_platform — prints one of: linux-amd64 linux-arm64 darwin-arm64 darwin-amd64
detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "${os}-${arch}" in
        Linux-x86_64)  printf 'linux-amd64' ;;
        Linux-aarch64) printf 'linux-arm64' ;;
        Darwin-arm64)  printf 'darwin-arm64' ;;
        Darwin-x86_64) printf 'darwin-amd64' ;;
        *)
            printf 'slopguard: unsupported platform %s-%s\n' "$os" "$arch" >&2
            return 1
            ;;
    esac
}

# --------------------------------------------------------------------------- #
# lockfile accessors — all read ${TOOLS_LOCK} at call time so tests can override it
# --------------------------------------------------------------------------- #

# _tools_lock — prints the lockfile path; errors if neither TOOLS_LOCK nor
# CLAUDE_PLUGIN_ROOT is available so callers see a named error instead of a
# bare bash "unbound variable" under set -u.
_tools_lock() {
    if [ -n "${TOOLS_LOCK:-}" ]; then
        printf '%s' "$TOOLS_LOCK"
    elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        printf '%s' "${CLAUDE_PLUGIN_ROOT}/tools/tools.lock.json"
    else
        printf 'slopguard: CLAUDE_PLUGIN_ROOT is not set (cannot locate tools.lock.json)\n' >&2
        return 1
    fi
}

# bootstrap_jq — install the pinned jq without requiring jq to parse its own lock entry.
# Prints the managed binary path. The deliberately small awk parser reads only
# string fields from the jq object; normal lock access uses jq after this step.
bootstrap_jq() {
    local lock platform version asset_line url expected_hash actual_hash
    local tools_base version_dir current_link download_dir stage_dir new_link
    local install_lock backup_dir=""
    lock="$(_tools_lock)" || return 1
    platform="$(detect_platform)" || return 1
    version="$(awk '
        /^[[:space:]]*"jq"[[:space:]]*:/ { in_jq = 1; next }
        in_jq && /^    "[^"]+"[[:space:]]*:/ { exit }
        in_jq && /"version"[[:space:]]*:/ {
            line = $0
            sub(/^.*"version"[[:space:]]*:[[:space:]]*"/, "", line)
            sub(/".*$/, "", line)
            print line
            exit
        }
    ' "$lock")"
    asset_line="$(awk -v platform="$platform" '
        /^[[:space:]]*"jq"[[:space:]]*:/ { in_jq = 1; next }
        in_jq && /^    "[^"]+"[[:space:]]*:/ { exit }
        in_jq && index($0, "\"" platform "\"") { print; exit }
    ' "$lock")"
    url="$(printf '%s\n' "$asset_line" | sed 's/^.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/')"
    expected_hash="$(printf '%s\n' "$asset_line" | sed 's/^.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/')"
    [ -n "$version" ] && [ -n "$asset_line" ] && [ "$url" != "$asset_line" ] && [ "$expected_hash" != "$asset_line" ] || {
        printf 'slopguard: jq bootstrap metadata missing for %s\n' "$platform" >&2
        return 1
    }

    tools_base="${CLAUDE_PLUGIN_DATA}/tools/jq"
    version_dir="${tools_base}/${version}"
    current_link="${tools_base}/current"
    if [ -x "${current_link}/jq" ] && "${current_link}/jq" --version 2>/dev/null | grep -qE "jq-${version}\$"; then
        printf '%s\n' "${current_link}/jq"
        return 0
    fi

    mkdir -p "$tools_base"
    install_lock="${tools_base}/.bootstrap.lock"
    mkdir "$install_lock" 2>/dev/null || {
        printf 'slopguard: jq bootstrap already in progress\n' >&2
        return 1
    }
    download_dir="$(mktemp -d)" || { rmdir "$install_lock"; return 1; }
    stage_dir="${tools_base}/.${version}.bootstrap.$$"
    trap 'rm -rf "$download_dir" "$stage_dir"; rmdir "$install_lock" 2>/dev/null || true' RETURN
    if ! curl -sSL --fail -o "${download_dir}/jq" "$url"; then
        printf 'slopguard: jq bootstrap download failed: %s\n' "$url" >&2
        rm -rf "$download_dir" "$stage_dir"
        trap - RETURN
        return 1
    fi
    actual_hash="$(_sha256 "${download_dir}/jq")" || return 1
    if [ "$actual_hash" != "$expected_hash" ]; then
        printf 'slopguard: jq bootstrap sha256 mismatch\n' >&2
        return 1
    fi
    mkdir -p "$stage_dir"
    cp "${download_dir}/jq" "${stage_dir}/jq" || return 1
    chmod +x "${stage_dir}/jq"
    if [ -e "$version_dir" ]; then
        backup_dir="${tools_base}/.${version}.backup.$$"
        mv "$version_dir" "$backup_dir" || return 1
    fi
    if ! mv "$stage_dir" "$version_dir"; then
        [ -n "$backup_dir" ] && mv "$backup_dir" "$version_dir"
        return 1
    fi
    new_link="${tools_base}/current.new.$$"
    ln -snf "$version_dir" "$new_link"
    if ! _mv_atomic_symlink "$new_link" "$current_link"; then
        rm -rf "$version_dir"
        [ -n "$backup_dir" ] && mv "$backup_dir" "$version_dir"
        return 1
    fi
    [ -n "$backup_dir" ] && rm -rf "$backup_dir"
    rm -rf "$download_dir"
    rmdir "$install_lock"
    trap - RETURN
    printf '%s\n' "${current_link}/jq"
}

# lock_field <tool> <platform> <field>  — prints the value or nothing
lock_field() {
    local tool="$1" platform="$2" field="$3"
    local lock; lock="$(_tools_lock)" || return 1
    jq -r --arg t "$tool" --arg p "$platform" --arg f "$field" \
        '.tools[$t].assets[$p][$f] // empty' "$lock"
}

# lock_version <tool>  — prints the version string or nothing
lock_version() {
    local tool="$1"
    local lock; lock="$(_tools_lock)" || return 1
    jq -r --arg t "$tool" '.tools[$t].version // empty' "$lock"
}

# lock_bin <tool>  — prints the binary name (defaults to tool name)
lock_bin() {
    local tool="$1"
    local lock; lock="$(_tools_lock)" || return 1
    jq -r --arg t "$tool" '.tools[$t].bin // $t' "$lock"
}

lock_metadata() {
    local tool="$1" field="$2"
    local lock; lock="$(_tools_lock)" || return 1
    jq -r --arg t "$tool" --arg f "$field" '.tools[$t][$f] // empty' "$lock"
}

# lock_tools  — prints every tool name, one per line; propagates jq stderr
lock_tools() {
    local lock; lock="$(_tools_lock)" || return 1
    jq -r '.tools | keys[]' "$lock"
}

# tool_config_path <tool> [project_dir]
# Prints the project config when present, otherwise the plugin baseline used by
# that tool. Tools without a config print "none".
tool_config_path() {
    local tool="$1" project_dir="${2:-${CLAUDE_PROJECT_DIR:-}}"
    local candidate
    case "$tool" in
        betterleaks)
            [ -n "$project_dir" ] && [ -f "${project_dir}/.gitleaks.toml" ] \
                && { printf '%s' "${project_dir}/.gitleaks.toml"; return; }
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.gitleaks.toml"
            ;;
        checkov)
            [ -n "$project_dir" ] && [ -f "${project_dir}/.checkov.yaml" ] \
                && { printf '%s' "${project_dir}/.checkov.yaml"; return; }
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.checkov.yaml"
            ;;
        eslint-stack)
            if [ -n "$project_dir" ]; then
                for candidate in "${project_dir}"/eslint.config.* "${project_dir}"/.eslintrc*; do
                    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
                done
            fi
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/eslint.config.mjs"
            ;;
        golangci-lint)
            if [ -n "$project_dir" ]; then
                for candidate in "${project_dir}"/.golangci.yml "${project_dir}"/.golangci.yaml \
                    "${project_dir}"/.golangci.toml "${project_dir}"/.golangci.json; do
                    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
                done
            fi
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.golangci.yml"
            ;;
        hadolint)
            [ -n "$project_dir" ] && [ -f "${project_dir}/.hadolint.yaml" ] \
                && { printf '%s' "${project_dir}/.hadolint.yaml"; return; }
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.hadolint.yaml"
            ;;
        jscpd)
            if [ -n "$project_dir" ]; then
                for candidate in "${project_dir}/.jscpd.json" "${project_dir}/.jscpd.jsonc"; do
                    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
                done
            fi
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.jscpd.json"
            ;;
        kube-linter)
            [ -n "$project_dir" ] && [ -f "${project_dir}/.kube-linter.yaml" ] \
                && { printf '%s' "${project_dir}/.kube-linter.yaml"; return; }
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.kube-linter.yaml"
            ;;
        opengrep)
            if [ -n "$project_dir" ]; then
                for candidate in "${project_dir}"/.semgrep.yml "${project_dir}"/.semgrep.yaml; do
                    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
                done
            fi
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/rules/opengrep"
            ;;
        phpstan)
            if [ -n "$project_dir" ]; then
                for candidate in "${project_dir}"/phpstan.neon "${project_dir}"/phpstan.neon.dist \
                    "${project_dir}"/phpstan.dist.neon; do
                    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
                done
            fi
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/phpstan.neon"
            ;;
        psalm)
            if [ -n "$project_dir" ]; then
                for candidate in "${project_dir}"/psalm.xml "${project_dir}"/psalm.xml.dist; do
                    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
                done
            fi
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/psalm.xml"
            ;;
        ruff)
            if [ -n "$project_dir" ]; then
                for candidate in "${project_dir}/ruff.toml" "${project_dir}/.ruff.toml"; do
                    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
                done
                if [ -f "${project_dir}/pyproject.toml" ] \
                    && grep -Eq '^\[tool\.ruff(\.|\])' "${project_dir}/pyproject.toml"; then
                    printf '%s' "${project_dir}/pyproject.toml"
                    return
                fi
            fi
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/ruff.toml"
            ;;
        tflint)
            [ -n "$project_dir" ] && [ -f "${project_dir}/.tflint.hcl" ] \
                && { printf '%s' "${project_dir}/.tflint.hcl"; return; }
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.tflint.hcl"
            ;;
        zizmor)
            [ -n "$project_dir" ] && [ -f "${project_dir}/zizmor.yml" ] \
                && { printf '%s' "${project_dir}/zizmor.yml"; return; }
            printf '%s' "${CLAUDE_PLUGIN_ROOT}/configs/baseline/zizmor.yml"
            ;;
        *)
            printf 'none'
            ;;
    esac
}

tool_config_source() {
    local config_path="$1"
    case "$config_path" in
        none) printf 'none' ;;
        "${CLAUDE_PLUGIN_ROOT}"/*) printf 'baseline' ;;
        *) printf 'project' ;;
    esac
}

# tool_config_mode <tool> [project_dir]
# Prints the effective run mode for this tool given the current project context:
#   project  — a project config is present; run with it and report everything
#   overlay  — no project config; run with baseline, report only security findings
#   full     — no project config; run with baseline, report everything
#   skip     — no project config; knob=project-only → do not run the tool
#
# Reads CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE (overlay|full|project-only); defaults to
# overlay.  An unrecognised value is treated as overlay so a config typo never
# disables the guard.
tool_config_mode() {
    local tool="$1" project_dir="${2:-${CLAUDE_PROJECT_DIR:-}}"
    local config_path source
    config_path="$(tool_config_path "$tool" "$project_dir")"
    source="$(tool_config_source "$config_path")"

    # When a project config exists the tool runs with it and reports everything.
    if [ "$source" = "project" ]; then
        printf 'project'
        return
    fi

    # No project config (baseline or none) — apply the knob.
    local knob="${CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE:-overlay}"
    case "$knob" in
        full)         printf 'full'    ;;
        project-only) printf 'skip'    ;;
        *)            printf 'overlay' ;;  # overlay and unrecognised values → overlay
    esac
}

# tool_version_output <name> <binary_path>
tool_version_output() {
    case "$1" in
        kube-linter) "$2" version 2>&1 ;;
        *) "$2" --version 2>&1 ;;
    esac
}

# --------------------------------------------------------------------------- #
# tool_version_matches
# --------------------------------------------------------------------------- #

# tool_version_matches <name> <binary_path>
# Returns 0 when the binary's --version output contains a version token that
# equals the lockfile version (leading 'v' stripped from both sides). Uses an
# exact equality check rather than a substring match to prevent 1.8.2 from
# matching 1.8.20.
tool_version_matches() {
    local name="$1" binary="$2"
    local expected; expected="$(lock_version "$name")" || return 1
    [ -n "$expected" ] || return 1
    expected="${expected#v}"   # strip leading 'v' (e.g. v0.11.0 → 0.11.0)

    local actual; actual="$(tool_version_output "$name" "$binary" || true)"
    # Extract the first dotted-integer version token from --version output.
    local actual_ver
    actual_ver="$(printf '%s\n' "$actual" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [ -z "$actual_ver" ] && \
        actual_ver="$(printf '%s\n' "$actual" | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    [ "$actual_ver" = "$expected" ]
}

# Managed Node tools are current only when the copied manifests still match the
# plugin. A plugin update can change transitive pins without changing ESLint's
# own version.
managed_metadata_matches() {
    local name="$1" node_lock source_dir target
    node_lock="$(lock_metadata "$name" node_lock)"
    [ -n "$node_lock" ] || return 0
    source_dir="${CLAUDE_PLUGIN_ROOT}/$(dirname "$node_lock")"
    target="${CLAUDE_PLUGIN_DATA}/tools/node"
    cmp -s "${source_dir}/package.json" "${target}/package.json" \
        && cmp -s "${source_dir}/package-lock.json" "${target}/package-lock.json"
}

# --------------------------------------------------------------------------- #
# resolve_tool
# --------------------------------------------------------------------------- #

# resolve_tool <name>
# Prints an absolute path or nothing. Reads CLAUDE_PLUGIN_OPTION_TOOL_SOURCE
# (project-first | plugin-only | project-only); defaults to project-first.
# Step 2 (plugin binary) is accepted only when its version matches the lockfile.
resolve_tool() {
    local name="$1"
    local source="${CLAUDE_PLUGIN_OPTION_TOOL_SOURCE:-project-first}"
    local found="" bin_name
    bin_name="$(lock_bin "$name")"

    # 1. Project binary (skipped in plugin-only mode).
    if [ "$source" != "plugin-only" ]; then
        local project_dir="${CLAUDE_PROJECT_DIR:-}"
        if [ -n "$project_dir" ]; then
            local candidate
            for candidate in \
                "${project_dir}/vendor/bin/${bin_name}" \
                "${project_dir}/node_modules/.bin/${bin_name}" \
                "${project_dir}/.venv/bin/${bin_name}"
            do
                if [ -x "$candidate" ]; then
                    found="$candidate"
                    break
                fi
            done
        fi
        # go tool -n prints the path without executing the tool (Go 1.24+).
        if [ -z "$found" ] && command -v go >/dev/null 2>&1; then
            local go_path
            go_path="$(go tool -n "$bin_name" 2>/dev/null)" || true
            if [ -n "$go_path" ] && [ -x "$go_path" ]; then
                found="$go_path"
            fi
        fi
    fi

    # 2. Plugin binary — accepted only when version matches the lockfile.
    #    (Skipped in project-only mode and when CLAUDE_PLUGIN_DATA is unset.)
    if [ -z "$found" ] && [ "$source" != "project-only" ] && [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
        local plugin_bin="${CLAUDE_PLUGIN_DATA}/tools/${name}/current/${bin_name}"
        if [ -x "$plugin_bin" ] \
            && managed_metadata_matches "$name" \
            && tool_version_matches "$name" "$plugin_bin"; then
            found="$plugin_bin"
        fi
    fi

    # 3. PATH binary — only when version matches the lockfile (§9.1).
    if [ -z "$found" ] && [ "$source" = "project-first" ]; then
        if command -v "$bin_name" >/dev/null 2>&1; then
            local path_bin; path_bin="$(command -v "$bin_name")"
            if tool_version_matches "$name" "$path_bin"; then
                found="$path_bin"
            fi
        fi
    fi

    printf '%s' "$found"
}

# --------------------------------------------------------------------------- #
# install_tool
# --------------------------------------------------------------------------- #

# install_tool <name>
# Download → verify sha256 → extract into version directory → atomic current swap.
# On hash mismatch: remove the download, remove any partial version dir, exit non-zero.
# Never writes under ${CLAUDE_PLUGIN_ROOT} (replaced on plugin update, §3.1).
_repoint_tool_current() {
    local name="$1" target="$2"
    local tools_base="${CLAUDE_PLUGIN_DATA}/tools/${name}"
    local new_link="${tools_base}/current.new.$$"
    mkdir -p "$tools_base"
    ln -snf "$target" "$new_link"
    _mv_atomic_symlink "$new_link" "${tools_base}/current"
}

install_python_tools() (
    local lock_rel lock_file target stage backup="" install_lock names tool bin_name
    command -v uv >/dev/null 2>&1 || {
        printf 'slopguard: uv is required to install Python tools\n' >&2
        exit 1
    }
    lock_rel="$(lock_metadata "$1" python_lock)"
    lock_file="${CLAUDE_PLUGIN_ROOT}/${lock_rel}"
    target="${CLAUDE_PLUGIN_DATA}/tools/python-venv"
    stage="${CLAUDE_PLUGIN_DATA}/tools/.python-venv.stage.$$"
    install_lock="${CLAUDE_PLUGIN_DATA}/tools/.python-venv.install.lock"
    mkdir -p "${CLAUDE_PLUGIN_DATA}/tools"
    mkdir "$install_lock" 2>/dev/null || {
        printf 'slopguard: Python tool install already in progress\n' >&2
        exit 1
    }
    trap 'rm -rf "$stage"; rmdir "$install_lock" 2>/dev/null || true' EXIT INT TERM HUP

    uv venv --relocatable --quiet "$stage" || exit 1
    uv pip install --quiet --python "${stage}/bin/python" --require-hashes -r "$lock_file" || exit 1
    names="$(jq -r '.tools | to_entries[] | select(.value.python_lock != null) | .key' "$(_tools_lock)")"
    while IFS= read -r tool; do
        [ -n "$tool" ] || continue
        bin_name="$(lock_bin "$tool")"
        [ -x "${stage}/bin/${bin_name}" ] && tool_version_matches "$tool" "${stage}/bin/${bin_name}" || {
            printf 'slopguard: Python tool verification failed: %s\n' "$tool" >&2
            exit 1
        }
    done <<< "$names"

    if [ -e "$target" ]; then
        backup="${CLAUDE_PLUGIN_DATA}/tools/.python-venv.backup.$$"
        mv "$target" "$backup" || exit 1
    fi
    if ! mv "$stage" "$target"; then
        [ -n "$backup" ] && mv "$backup" "$target"
        exit 1
    fi
    while IFS= read -r tool; do
        [ -n "$tool" ] || continue
        _repoint_tool_current "$tool" "${target}/bin" || exit 1
    done <<< "$names"
    if [ -n "$backup" ]; then rm -rf "$backup"; fi
    printf 'slopguard: installed pinned Python tools\n' >&2
)

install_node_tools() (
    local lock_rel source_dir target stage backup="" install_lock bin_name
    command -v npm >/dev/null 2>&1 || {
        printf 'slopguard: npm is required to install Node tools\n' >&2
        exit 1
    }
    lock_rel="$(lock_metadata "$1" node_lock)"
    source_dir="${CLAUDE_PLUGIN_ROOT}/$(dirname "$lock_rel")"
    target="${CLAUDE_PLUGIN_DATA}/tools/node"
    stage="${CLAUDE_PLUGIN_DATA}/tools/.node.stage.$$"
    install_lock="${CLAUDE_PLUGIN_DATA}/tools/.node.install.lock"
    mkdir -p "${CLAUDE_PLUGIN_DATA}/tools"
    mkdir "$install_lock" 2>/dev/null || {
        printf 'slopguard: Node tool install already in progress\n' >&2
        exit 1
    }
    trap 'rm -rf "$stage"; rmdir "$install_lock" 2>/dev/null || true' EXIT INT TERM HUP

    mkdir -p "$stage"
    cp "${source_dir}/package.json" "${source_dir}/package-lock.json" "$stage/"
    (cd "$stage" && npm ci --ignore-scripts --quiet) || exit 1
    bin_name="$(lock_bin "$1")"
    [ -x "${stage}/node_modules/.bin/${bin_name}" ] && \
        tool_version_matches "$1" "${stage}/node_modules/.bin/${bin_name}" || {
        printf 'slopguard: Node tool verification failed: %s\n' "$1" >&2
        exit 1
    }

    if [ -e "$target" ]; then
        backup="${CLAUDE_PLUGIN_DATA}/tools/.node.backup.$$"
        mv "$target" "$backup" || exit 1
    fi
    if ! mv "$stage" "$target"; then
        [ -n "$backup" ] && mv "$backup" "$target"
        exit 1
    fi
    _repoint_tool_current "$1" "${target}/node_modules/.bin" || exit 1
    if [ -n "$backup" ]; then rm -rf "$backup"; fi
    printf 'slopguard: installed pinned Node tools\n' >&2
)

install_tool() {
    local name="$1" platform version url expected_hash bin_name
    platform="$(detect_platform)" || return 1

    [ -n "${CLAUDE_PLUGIN_DATA:-}" ] || {
        printf 'slopguard: CLAUDE_PLUGIN_DATA is not set\n' >&2
        return 1
    }

    if [ -n "$(lock_metadata "$name" python_lock)" ]; then
        install_python_tools "$name"
        return
    fi
    if [ -n "$(lock_metadata "$name" node_lock)" ]; then
        install_node_tools "$name"
        return
    fi

    version="$(lock_version "$name")"
    url="$(lock_field "$name" "$platform" url)"
    expected_hash="$(lock_field "$name" "$platform" sha256)"
    bin_name="$(lock_bin "$name")"
    [ -n "$url" ] || { printf 'slopguard: no asset for %s on %s\n' "$name" "$platform" >&2; return 1; }
    [ -n "$expected_hash" ] || { printf 'slopguard: no sha256 for %s on %s\n' "$name" "$platform" >&2; return 1; }
    [ -n "$version" ] || { printf 'slopguard: no version for %s\n' "$name" >&2; return 1; }

    local tools_base="${CLAUDE_PLUGIN_DATA}/tools/${name}"
    local version_dir="${tools_base}/${version}"
    local current_link="${tools_base}/current"
    local install_lock="${tools_base}/.install.lock"
    mkdir -p "$tools_base"
    if ! mkdir "$install_lock" 2>/dev/null; then
        printf 'slopguard: install already in progress for %s\n' "$name" >&2
        return 1
    fi

    (
        local download_dir stage_dir asset_file asset_name actual_hash
        local backup_dir="" new_link zip_scratch zip_top_count zip_top
        download_dir="$(mktemp -d)" || exit 1
        stage_dir="${tools_base}/.${version}.stage.$$"
        asset_file="${download_dir}/asset"
        rm -rf "$stage_dir"
        mkdir -p "$stage_dir"
        trap 'rm -rf "$download_dir" "$stage_dir"; rmdir "$install_lock" 2>/dev/null || true' EXIT INT TERM HUP

        printf 'slopguard: downloading %s %s...\n' "$name" "$version" >&2
        if ! curl -sSL --fail -o "$asset_file" "$url"; then
            printf 'slopguard: download failed: %s\n' "$url" >&2
            exit 1
        fi
        actual_hash="$(_sha256 "$asset_file")"
        if [ "$actual_hash" != "$expected_hash" ]; then
            printf 'slopguard: sha256 mismatch for %s\n' "$name" >&2
            printf '  expected: %s\n  actual:   %s\n' "$expected_hash" "$actual_hash" >&2
            exit 1
        fi

        asset_name="$(basename "$url")"
        case "$asset_name" in
            *.tar.gz|*.tgz)
                zip_scratch="${download_dir}/archive-extract"
                mkdir -p "$zip_scratch"
                tar -xzf "$asset_file" -C "$zip_scratch" || exit 1 ;;
            *.tar.xz)
                zip_scratch="${download_dir}/archive-extract"
                mkdir -p "$zip_scratch"
                tar -xJf "$asset_file" -C "$zip_scratch" || exit 1 ;;
            *.zip)
                zip_scratch="${download_dir}/archive-extract"
                mkdir -p "$zip_scratch"
                unzip -q "$asset_file" -d "$zip_scratch" || exit 1 ;;
            *)
                cp "$asset_file" "${stage_dir}/${bin_name}" || exit 1
                chmod +x "${stage_dir}/${bin_name}" ;;
        esac
        if [ -n "${zip_scratch:-}" ]; then
            zip_top_count="$(ls -1A "$zip_scratch" | wc -l | tr -d ' ')"
            zip_top="$(ls -1A "$zip_scratch" | head -1)"
            if [ "$zip_top_count" -eq 1 ] && [ -d "${zip_scratch}/${zip_top}" ]; then
                cp -a "${zip_scratch}/${zip_top}/." "$stage_dir/"
            else
                cp -a "${zip_scratch}/." "$stage_dir/"
            fi
        fi

        if [ ! -x "${stage_dir}/${bin_name}" ]; then
            printf 'slopguard: binary not found after install: %s/%s\n' "$stage_dir" "$bin_name" >&2
            exit 1
        fi
        if ! tool_version_matches "$name" "${stage_dir}/${bin_name}"; then
            printf 'slopguard: installed %s binary reports the wrong version\n' "$name" >&2
            exit 1
        fi
        if [ "$name" = "tflint" ]; then
            local tflint_plugins="${CLAUDE_PLUGIN_DATA}/tools/tflint/plugins"
            mkdir -p "$tflint_plugins"
            if ! env TFLINT_PLUGIN_DIR="$tflint_plugins" "${stage_dir}/${bin_name}" \
                --config "${CLAUDE_PLUGIN_ROOT}/configs/baseline/.tflint.hcl" \
                --init >/dev/null 2>&1; then
                printf 'slopguard: failed to install the pinned tflint AWS ruleset\n' >&2
                exit 1
            fi
        fi


        if [ -e "$version_dir" ] || [ -L "$version_dir" ]; then
            backup_dir="${tools_base}/.${version}.backup.$$"
            mv "$version_dir" "$backup_dir" || exit 1
        fi
        if ! mv "$stage_dir" "$version_dir"; then
            [ -n "$backup_dir" ] && mv "$backup_dir" "$version_dir"
            exit 1
        fi

        new_link="${tools_base}/current.new.$$"
        ln -snf "$version_dir" "$new_link"
        if ! _mv_atomic_symlink "$new_link" "$current_link"; then
            rm -f "$new_link"
            rm -rf "$version_dir"
            [ -n "$backup_dir" ] && mv "$backup_dir" "$version_dir"
            exit 1
        fi
        [ -n "$backup_dir" ] && rm -rf "$backup_dir"
        printf 'slopguard: installed %s %s at %s\n' "$name" "$version" "$version_dir" >&2
    )
}
