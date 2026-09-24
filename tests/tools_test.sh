#!/usr/bin/env bash
# tools_test.sh — installer and resolver tests.
#
# Sourced by tests/run-tests; ok() and bad() are pre-defined there.
# Needs no network: assets are served from file:// URLs.
# Asserts on the filesystem, not on log text.

# --------------------------------------------------------------------------- #
# Setup: temp workspace and cleanup trap
# --------------------------------------------------------------------------- #

TEST_WORK="${TMPDIR:-/tmp}/slop-guard-tools-test-$$"
mkdir -p "$TEST_WORK"
# Clean up on exit even if a test case causes an unexpected abort.
trap 'rm -rf "${TEST_WORK}"' EXIT INT TERM

# Source the library with CLAUDE_PLUGIN_ROOT pointing at the real plugin root.
# TOOLS_LOCK and CLAUDE_PLUGIN_DATA are overridden inside subshells per test.
# shellcheck source=../lib/tools.sh
. "${PLUGIN_ROOT}/lib/tools.sh"

# --------------------------------------------------------------------------- #
# Fake assets and lockfiles (two versions for the upgrade test)
# --------------------------------------------------------------------------- #

# Version 9.9.9 asset: fake-tool-9.9.9/fake-tool inside the tar.
FAKE_TARDIR="${TEST_WORK}/tardir/fake-tool-9.9.9"
mkdir -p "$FAKE_TARDIR"
printf '#!/bin/sh\nprintf "fake-tool 9.9.9\\n"\n' > "${FAKE_TARDIR}/fake-tool"
chmod +x "${FAKE_TARDIR}/fake-tool"
FAKE_TAR="${TEST_WORK}/fake-tool-9.9.9.tar.gz"
tar -czf "$FAKE_TAR" -C "${TEST_WORK}/tardir" "fake-tool-9.9.9"
GOOD_HASH="$(_sha256 "$FAKE_TAR")"
BAD_HASH="0000000000000000000000000000000000000000000000000000000000000000"

# Version 10.0.0 asset: used for the upgrade (atomic mv) test.
FAKE_TARDIR2="${TEST_WORK}/tardir2/fake-tool-10.0.0"
mkdir -p "$FAKE_TARDIR2"
printf '#!/bin/sh\nprintf "fake-tool 10.0.0\\n"\n' > "${FAKE_TARDIR2}/fake-tool"
chmod +x "${FAKE_TARDIR2}/fake-tool"
FAKE_TAR2="${TEST_WORK}/fake-tool-10.0.0.tar.gz"
tar -czf "$FAKE_TAR2" -C "${TEST_WORK}/tardir2" "fake-tool-10.0.0"
GOOD_HASH2="$(_sha256 "$FAKE_TAR2")"

# Lockfile: good hash for 9.9.9
FAKE_LOCK="${TEST_WORK}/tools.lock.json"
jq -n \
    --arg url "file://${FAKE_TAR}" \
    --arg good "$GOOD_HASH" \
    '{schema:1, tools:{"fake-tool":{version:"9.9.9",
        assets:{"linux-amd64":{url:$url,sha256:$good},
                "linux-arm64":{url:$url,sha256:$good},
                "darwin-arm64":{url:$url,sha256:$good}},
        bin:"fake-tool"}}}' > "$FAKE_LOCK"

# Lockfile: bad hash for 9.9.9
BAD_LOCK="${TEST_WORK}/bad.lock.json"
jq -n \
    --arg url "file://${FAKE_TAR}" \
    --arg bad "$BAD_HASH" \
    '{schema:1, tools:{"fake-tool":{version:"9.9.9",
        assets:{"linux-amd64":{url:$url,sha256:$bad},
                "linux-arm64":{url:$url,sha256:$bad},
                "darwin-arm64":{url:$url,sha256:$bad}},
        bin:"fake-tool"}}}' > "$BAD_LOCK"

# Lockfile: good hash for 10.0.0
UPGRADE_LOCK="${TEST_WORK}/upgrade.lock.json"
jq -n \
    --arg url "file://${FAKE_TAR2}" \
    --arg hash "$GOOD_HASH2" \
    '{schema:1, tools:{"fake-tool":{version:"10.0.0",
        assets:{"linux-amd64":{url:$url,sha256:$hash},
                "linux-arm64":{url:$url,sha256:$hash},
                "darwin-arm64":{url:$url,sha256:$hash}},
        bin:"fake-tool"}}}' > "$UPGRADE_LOCK"

# Raw jq fixture: bootstrap_jq must parse and install it before jq is available
# for normal lockfile access.
FAKE_JQ="${TEST_WORK}/jq"
printf '#!/bin/sh\nprintf "jq-9.9.9\\n"\n' > "$FAKE_JQ"
chmod +x "$FAKE_JQ"
FAKE_JQ_HASH="$(_sha256 "$FAKE_JQ")"
FAKE_JQ_LOCK="${TEST_WORK}/jq-bootstrap.lock.json"
cat > "$FAKE_JQ_LOCK" <<EOF
{
  "schema": 1,
  "tools": {
    "jq": {
      "version": "9.9.9",
      "assets": {
        "linux-amd64": { "url": "file://${FAKE_JQ}", "sha256": "${FAKE_JQ_HASH}" },
        "linux-arm64": { "url": "file://${FAKE_JQ}", "sha256": "${FAKE_JQ_HASH}" },
        "darwin-amd64": { "url": "file://${FAKE_JQ}", "sha256": "${FAKE_JQ_HASH}" },
        "darwin-arm64": { "url": "file://${FAKE_JQ}", "sha256": "${FAKE_JQ_HASH}" }
      },
      "bin": "jq"
    }
  }
}
EOF

printf '\ninstaller: jq bootstraps from its lock entry without jq parsing\n'
FAKE_DATA_JQ="${TEST_WORK}/plugin-data-jq"
bootstrapped_jq=$(
    TOOLS_LOCK="$FAKE_JQ_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_JQ"
    bootstrap_jq
); rc_jq=$?
[ "$rc_jq" -eq 0 ] && [ "$("$bootstrapped_jq" --version)" = "jq-9.9.9" ] \
    && ok "jq bootstrap installs and returns the pinned binary" \
    || bad "jq bootstrap" "path='${bootstrapped_jq}', rc=${rc_jq}"

# --------------------------------------------------------------------------- #
printf 'installer: good hash installs and points current at the version dir\n'
# --------------------------------------------------------------------------- #

FAKE_DATA_GOOD="${TEST_WORK}/plugin-data-good"
(
    TMPDIR="${TEST_WORK}/tmpdir-good"; mkdir -p "$TMPDIR"
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_GOOD"
    install_tool "fake-tool" >/dev/null 2>&1
); rc_good=$?

[ "$rc_good" -eq 0 ] && ok "exits zero on good hash" || bad "exit code (good hash)" "expected 0, got $rc_good"

version_dir_good="${FAKE_DATA_GOOD}/tools/fake-tool/9.9.9"
current_link_good="${FAKE_DATA_GOOD}/tools/fake-tool/current"

[ -d "$version_dir_good" ] && ok "version dir created" || bad "version dir" "missing: $version_dir_good"
[ -L "$current_link_good" ] && ok "current is a symlink" || bad "current symlink" "not a symlink: $current_link_good"
[ -x "${version_dir_good}/fake-tool" ] && ok "binary is executable" || bad "binary" "not executable in $version_dir_good"
[ "$(readlink "$current_link_good")" = "$version_dir_good" ] \
    && ok "current points at version dir" \
    || bad "current target" "$(readlink "$current_link_good" 2>/dev/null) != $version_dir_good"

# --------------------------------------------------------------------------- #
printf '\ninstaller: bad hash leaves no version dir, removes download, exits non-zero\n'
# --------------------------------------------------------------------------- #

FAKE_DATA_BAD="${TEST_WORK}/plugin-data-bad"
# Control TMPDIR so we can assert the download was removed.
CONTROLLED_TMPDIR="${TEST_WORK}/tmpdir-bad"
mkdir -p "$CONTROLLED_TMPDIR"
(
    export TMPDIR="$CONTROLLED_TMPDIR"
    TOOLS_LOCK="$BAD_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_BAD"
    install_tool "fake-tool" >/dev/null 2>&1
); rc_bad=$?

[ "$rc_bad" -ne 0 ] && ok "exits non-zero on bad hash" || bad "exit code (bad hash)" "expected non-zero, got $rc_bad"

version_dir_bad="${FAKE_DATA_BAD}/tools/fake-tool/9.9.9"
[ ! -d "$version_dir_bad" ] && ok "no version dir on hash mismatch" || bad "version dir" "exists but should not: $version_dir_bad"

# The download went to a mktemp dir under CONTROLLED_TMPDIR; install_tool removes
# it on mismatch. Assert nothing remains.
leftover_count="$(find "$CONTROLLED_TMPDIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$leftover_count" -eq 0 ] && ok "no leftover download in tmpdir" || bad "leftover download" "${leftover_count} file(s) in tmpdir"

# --------------------------------------------------------------------------- #
printf '\ninstaller: upgrade atomically repoints current to the new version dir\n'
# --------------------------------------------------------------------------- #

FAKE_DATA_UP="${TEST_WORK}/plugin-data-upgrade"

# First install: 9.9.9.
(
    TMPDIR="${TEST_WORK}/tmpdir-up1"; mkdir -p "$TMPDIR"
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_UP"
    install_tool "fake-tool" >/dev/null 2>&1
)

# Second install: 10.0.0 (upgrade over existing 9.9.9).
(
    TMPDIR="${TEST_WORK}/tmpdir-up2"; mkdir -p "$TMPDIR"
    TOOLS_LOCK="$UPGRADE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_UP"
    install_tool "fake-tool" >/dev/null 2>&1
); rc_up=$?

[ "$rc_up" -eq 0 ] && ok "upgrade exits zero" || bad "upgrade exit" "expected 0, got $rc_up"

v10_dir="${FAKE_DATA_UP}/tools/fake-tool/10.0.0"
[ -d "$v10_dir" ] && ok "10.0.0 version dir created" || bad "10.0.0 dir" "missing: $v10_dir"

cur_target="$(readlink "${FAKE_DATA_UP}/tools/fake-tool/current" 2>/dev/null)"
[ "$cur_target" = "$v10_dir" ] \
    && ok "current points at 10.0.0 dir" \
    || bad "current target after upgrade" "got '${cur_target}', want '${v10_dir}'"

# Assert no stray current.new.* inside the old 9.9.9 dir (the mv -fT fix).
stray_count="$(find "${FAKE_DATA_UP}/tools/fake-tool/9.9.9" -name "current.new.*" 2>/dev/null | wc -l | tr -d ' ')"
[ "$stray_count" -eq 0 ] \
    && ok "no stray symlink left inside old version dir" \
    || bad "stray symlink" "${stray_count} stray file(s) in 9.9.9/"

# --------------------------------------------------------------------------- #
printf '\nresolver: project binary wins over plugin-installed binary (project-first)\n'
# --------------------------------------------------------------------------- #

# Pre-build a plugin-installed tree (version-matching so step 2 accepts it).
FAKE_DATA_PREC="${TEST_WORK}/plugin-data-prec"
mkdir -p "${FAKE_DATA_PREC}/tools/fake-tool/9.9.9"
printf '#!/bin/sh\nprintf "fake-tool 9.9.9\\n"\n' \
    > "${FAKE_DATA_PREC}/tools/fake-tool/9.9.9/fake-tool"
chmod +x "${FAKE_DATA_PREC}/tools/fake-tool/9.9.9/fake-tool"
ln -s "${FAKE_DATA_PREC}/tools/fake-tool/9.9.9" "${FAKE_DATA_PREC}/tools/fake-tool/current"

# A fake project-local binary.
PROJECT_DIR="${TEST_WORK}/project"
mkdir -p "${PROJECT_DIR}/vendor/bin"
printf '#!/bin/sh\nprintf "fake-tool 9.9.9\\n"\n' \
    > "${PROJECT_DIR}/vendor/bin/fake-tool"
chmod +x "${PROJECT_DIR}/vendor/bin/fake-tool"

resolved_pf=$(
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_PREC"
    CLAUDE_PROJECT_DIR="$PROJECT_DIR"
    CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="project-first"
    resolve_tool "fake-tool"
)
[ "$resolved_pf" = "${PROJECT_DIR}/vendor/bin/fake-tool" ] \
    && ok "project-first: project binary wins over plugin" \
    || bad "project-first precedence" "got '${resolved_pf}'"

# --------------------------------------------------------------------------- #
printf '\nresolver: plugin-only mode ignores project binary\n'
# --------------------------------------------------------------------------- #

resolved_po=$(
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_PREC"
    CLAUDE_PROJECT_DIR="$PROJECT_DIR"
    CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="plugin-only"
    resolve_tool "fake-tool"
)
expected_plugin="${FAKE_DATA_PREC}/tools/fake-tool/current/fake-tool"
[ "$resolved_po" = "$expected_plugin" ] \
    && ok "plugin-only: returns plugin binary" \
    || bad "plugin-only" "got '${resolved_po}', want '${expected_plugin}'"

# --------------------------------------------------------------------------- #
printf '\nresolver: project-only mode ignores plugin binary\n'
# --------------------------------------------------------------------------- #

# Arrange: CLAUDE_PROJECT_DIR has no fake-tool, so step 1 finds nothing.
# With the step-2 guard intact, resolve_tool must return empty (plugin skipped).
# Without the guard, step 2 would return the plugin binary — the test goes red.
EMPTY_PROJECT_DIR="${TEST_WORK}/empty-project"
mkdir -p "$EMPTY_PROJECT_DIR"

resolved_proj=$(
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_PREC"
    CLAUDE_PROJECT_DIR="$EMPTY_PROJECT_DIR"
    CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="project-only"
    resolve_tool "fake-tool"
)
[ -z "$resolved_proj" ] \
    && ok "project-only: plugin binary ignored when project has none" \
    || bad "project-only guard" "got '${resolved_proj}', want empty"

# --------------------------------------------------------------------------- #
printf '\nresolver: plugin binary with wrong version is not accepted; install repairs it\n'
# --------------------------------------------------------------------------- #

# Plugin has 8.8.8 but lockfile wants 9.9.9.
FAKE_DATA_MM="${TEST_WORK}/plugin-data-mismatch"
mkdir -p "${FAKE_DATA_MM}/tools/fake-tool/8.8.8"
printf '#!/bin/sh\nprintf "fake-tool 8.8.8\\n"\n' \
    > "${FAKE_DATA_MM}/tools/fake-tool/8.8.8/fake-tool"
chmod +x "${FAKE_DATA_MM}/tools/fake-tool/8.8.8/fake-tool"
ln -s "${FAKE_DATA_MM}/tools/fake-tool/8.8.8" "${FAKE_DATA_MM}/tools/fake-tool/current"

# resolve_tool must return nothing (8.8.8 ≠ 9.9.9).
resolved_mm=$(
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_MM"
    resolve_tool "fake-tool"
)
[ -z "$resolved_mm" ] \
    && ok "mismatched plugin binary not accepted" \
    || bad "version gate" "got '${resolved_mm}'"

# After install_tool, resolve_tool returns the correct 9.9.9 binary.
(
    TMPDIR="${TEST_WORK}/tmpdir-mm"; mkdir -p "$TMPDIR"
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_MM"
    install_tool "fake-tool" >/dev/null 2>&1
)

resolved_after=$(
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_MM"
    resolve_tool "fake-tool"
)
expected_after="${FAKE_DATA_MM}/tools/fake-tool/current/fake-tool"
[ "$resolved_after" = "$expected_after" ] \
    && ok "resolve_tool finds 9.9.9 after repair install" \
    || bad "repair install" "got '${resolved_after}'"

# --------------------------------------------------------------------------- #
printf '\ninstaller: mv failure on same-version reinstall preserves live install\n'
# --------------------------------------------------------------------------- #

# Pre-install 9.9.9 — this becomes the live install that must survive.
FAKE_DATA_REINST="${TEST_WORK}/plugin-data-reinst"
(
    TMPDIR="${TEST_WORK}/tmpdir-reinst1"; mkdir -p "$TMPDIR"
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_REINST"
    install_tool "fake-tool" >/dev/null 2>&1
)

reinst_version_dir="${FAKE_DATA_REINST}/tools/fake-tool/9.9.9"
reinst_current="${FAKE_DATA_REINST}/tools/fake-tool/current"

# Simulate a same-version reinstall where the atomic mv fails.
# Override _mv_atomic_symlink in the subshell — both install_tool and the
# helper are bash functions, so the subshell inherits and can override them.
(
    _mv_atomic_symlink() { return 1; }
    TMPDIR="${TEST_WORK}/tmpdir-reinst2"; mkdir -p "$TMPDIR"
    TOOLS_LOCK="$FAKE_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_REINST"
    install_tool "fake-tool" >/dev/null 2>&1
); rc_reinst=$?

[ "$rc_reinst" -ne 0 ] \
    && ok "mv-failure reinstall: install_tool returns non-zero" \
    || bad "mv-failure reinstall exit" "expected non-zero, got $rc_reinst"

reinst_target="$(readlink "$reinst_current" 2>/dev/null)"
[ "$reinst_target" = "$reinst_version_dir" ] \
    && ok "mv-failure reinstall: current still resolves to live version dir" \
    || bad "mv-failure reinstall symlink" "got '${reinst_target}', want '${reinst_version_dir}'"

[ -x "${reinst_version_dir}/fake-tool" ] \
    && ok "mv-failure reinstall: binary still executable" \
    || bad "mv-failure reinstall binary" "not executable: ${reinst_version_dir}/fake-tool"

# --------------------------------------------------------------------------- #
printf '\ninstaller: zip with hidden top-level sibling is not silently discarded\n'
# --------------------------------------------------------------------------- #

# Build a zip whose top level is one directory (fake-tool-9.9.9/) plus one
# dotfile (.config).  ls -1 counts only the visible directory (count=1), so
# the strip branch runs and cp silently drops .config.  ls -1A (the fix)
# counts 2 and takes the flat-copy path, preserving both entries.
#
# The lockfile's bin field is "fake-tool-9.9.9/fake-tool": after a flat copy
# the binary lives at that sub-path inside version_dir, so the binary check
# passes with the fix and fails with the old code (strip moves the binary up
# one level, but the check looks in the wrong place).
DOTZIP_BUILD="${TEST_WORK}/dotzip-build"
DOTZIP_SUBDIR="${DOTZIP_BUILD}/fake-tool-9.9.9"
mkdir -p "$DOTZIP_SUBDIR"
printf '#!/bin/sh\nprintf "fake-tool 9.9.9\\n"\n' > "${DOTZIP_SUBDIR}/fake-tool"
chmod +x "${DOTZIP_SUBDIR}/fake-tool"
printf 'hidden config\n' > "${DOTZIP_BUILD}/.config"
DOTZIP="${TEST_WORK}/fake-dotfile.zip"
( cd "$DOTZIP_BUILD" && zip -q "$DOTZIP" fake-tool-9.9.9/fake-tool .config )
DOTZIP_HASH="$(_sha256 "$DOTZIP")"

DOTZIP_LOCK="${TEST_WORK}/dotzip.lock.json"
jq -n \
    --arg url "file://${DOTZIP}" \
    --arg hash "$DOTZIP_HASH" \
    '{schema:1, tools:{"fake-tool":{version:"9.9.9",
        assets:{"linux-amd64":{url:$url,sha256:$hash},
                "linux-arm64":{url:$url,sha256:$hash},
                "darwin-arm64":{url:$url,sha256:$hash}},
        bin:"fake-tool-9.9.9/fake-tool"}}}' > "$DOTZIP_LOCK"

FAKE_DATA_DOTZIP="${TEST_WORK}/plugin-data-dotzip"
(
    TMPDIR="${TEST_WORK}/tmpdir-dotzip"; mkdir -p "$TMPDIR"
    TOOLS_LOCK="$DOTZIP_LOCK"
    CLAUDE_PLUGIN_DATA="$FAKE_DATA_DOTZIP"
    install_tool "fake-tool" >/dev/null 2>&1
); rc_dotzip=$?

[ "$rc_dotzip" -eq 0 ] \
    && ok "zip-dotfile: install exits zero" \
    || bad "zip-dotfile install" "expected 0, got $rc_dotzip"

dotzip_version_dir="${FAKE_DATA_DOTZIP}/tools/fake-tool/9.9.9"
[ -f "${dotzip_version_dir}/.config" ] \
    && ok "zip-dotfile: .config survives in version dir" \
    || bad "zip-dotfile .config" "missing: ${dotzip_version_dir}/.config"

# --------------------------------------------------------------------------- #
printf '\nresolver: changed Node lockfiles invalidate the managed bundle\n'
# --------------------------------------------------------------------------- #

NODE_ROOT="${TEST_WORK}/node-plugin"
NODE_DATA="${TEST_WORK}/node-data"
NODE_LOCK="${NODE_ROOT}/tools/tools.lock.json"
mkdir -p "${NODE_ROOT}/tools/node" \
    "${NODE_DATA}/tools/node" \
    "${NODE_DATA}/tools/eslint-stack/9.9.9"
printf '{"private":true}\n' > "${NODE_ROOT}/tools/node/package.json"
printf '{"lockfileVersion":3,"packages":{}}\n' > "${NODE_ROOT}/tools/node/package-lock.json"
cp "${NODE_ROOT}/tools/node/package.json" "${NODE_ROOT}/tools/node/package-lock.json" \
    "${NODE_DATA}/tools/node/"
printf '#!/bin/sh\nprintf "eslint 9.9.9\\n"\n' \
    > "${NODE_DATA}/tools/eslint-stack/9.9.9/eslint"
chmod +x "${NODE_DATA}/tools/eslint-stack/9.9.9/eslint"
ln -s "${NODE_DATA}/tools/eslint-stack/9.9.9" \
    "${NODE_DATA}/tools/eslint-stack/current"
jq -n '{schema:1, tools:{"eslint-stack":{
    version:"9.9.9", bin:"eslint", node_lock:"tools/node/package-lock.json"}}}' \
    > "$NODE_LOCK"

node_resolved="$(
    TOOLS_LOCK="$NODE_LOCK"
    CLAUDE_PLUGIN_ROOT="$NODE_ROOT"
    CLAUDE_PLUGIN_DATA="$NODE_DATA"
    CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="plugin-only"
    resolve_tool "eslint-stack"
)"
printf '{"lockfileVersion":3,"packages":{"changed":{}}}\n' \
    > "${NODE_ROOT}/tools/node/package-lock.json"
node_stale="$(
    TOOLS_LOCK="$NODE_LOCK"
    CLAUDE_PLUGIN_ROOT="$NODE_ROOT"
    CLAUDE_PLUGIN_DATA="$NODE_DATA"
    CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="plugin-only"
    resolve_tool "eslint-stack"
)"
if [ -n "$node_resolved" ] && [ -z "$node_stale" ]; then
    ok "Node bundle is rejected when the plugin lockfile changes"
else
    bad "Node lockfile freshness" \
        "before='${node_resolved}' after='${node_stale}'"
fi

# --------------------------------------------------------------------------- #
printf '\ndoctor: empty-resolution after install does not blame precedence\n'
# --------------------------------------------------------------------------- #

# project-only source mode: step 2 (plugin binary) is always skipped, so a
# tool installed to the plugin data dir cannot be resolved.  The post-install
# message must say the binary is unreachable in the current source mode, not
# that a higher-priority binary is competing (none is).
FAKE_DATA_PO2="${TEST_WORK}/plugin-data-po2"
po2_out="${TEST_WORK}/po2-output.txt"
(
    export TMPDIR="${TEST_WORK}/tmpdir-po2"; mkdir -p "$TMPDIR"
    export TOOLS_LOCK="$FAKE_LOCK"
    export CLAUDE_PLUGIN_DATA="$FAKE_DATA_PO2"
    export CLAUDE_PROJECT_DIR="$EMPTY_PROJECT_DIR"
    export CLAUDE_PLUGIN_OPTION_TOOL_SOURCE="project-only"
    export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
    # --all: this check is about install precedence, not stack scoping, and the
    # synthetic lockfile's tool belongs to no stack.
    "${PLUGIN_ROOT}/bin/slopguard" doctor --install --all 2>/dev/null
) > "$po2_out" 2>&1

if grep -qF "higher-priority binary" "$po2_out"; then
    bad "project-only post-install message" "blamed precedence; want 'not reachable' message"
elif grep -q "not reachable in the current source mode" "$po2_out"; then
    ok "project-only: empty-resolution does not blame precedence"
else
    bad "project-only post-install message" \
        "neither expected phrase; output: $(cat "$po2_out")"
fi
