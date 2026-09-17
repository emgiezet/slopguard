#!/usr/bin/env bash
# tests/config_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.
#
# Covers every row of the config_resolve_stacks resolution table.

# shellcheck source=../lib/detect.sh
. "${PLUGIN_ROOT}/lib/detect.sh"
# shellcheck source=../lib/config.sh
. "${PLUGIN_ROOT}/lib/config.sh"

CONFIG_WORK="${TMPDIR:-/tmp}/slopguard-config-test-$$"
mkdir -p "$CONFIG_WORK"

# Ensure no stale SLOPGUARD_CONFIG_FILE from the environment leaks in.
unset SLOPGUARD_CONFIG_FILE 2>/dev/null || true

# --------------------------------------------------------------------------- #
# 1. Absent file → auto, no warning
# --------------------------------------------------------------------------- #

_c1="${CONFIG_WORK}/absent"
mkdir -p "$_c1"
config_resolve_stacks "$_c1"

[ "$SG_STACKS_SOURCE" = "auto" ] \
    && ok  "config: absent .slopguard.json → source=auto" \
    || bad "config: absent .slopguard.json → source=auto" "got: $SG_STACKS_SOURCE"

[ -z "$SG_STACKS_WARNINGS" ] \
    && ok  "config: absent .slopguard.json → no warnings" \
    || bad "config: absent .slopguard.json → no warnings" "got: $SG_STACKS_WARNINGS"

# --------------------------------------------------------------------------- #
# 2. Empty object {} → auto, no warning
# --------------------------------------------------------------------------- #

_c2="${CONFIG_WORK}/empty-obj"
mkdir -p "$_c2"
printf '{}' > "${_c2}/.slopguard.json"
config_resolve_stacks "$_c2"

[ "$SG_STACKS_SOURCE" = "auto" ] \
    && ok  "config: {} → source=auto" \
    || bad "config: {} → source=auto" "got: $SG_STACKS_SOURCE"

[ -z "$SG_STACKS_WARNINGS" ] \
    && ok  "config: {} → no warnings" \
    || bad "config: {} → no warnings" "got: $SG_STACKS_WARNINGS"

# --------------------------------------------------------------------------- #
# 3. Unparseable JSON → auto + warning
# --------------------------------------------------------------------------- #

_c3="${CONFIG_WORK}/bad-json"
mkdir -p "$_c3"
printf '{bad json not valid' > "${_c3}/.slopguard.json"
config_resolve_stacks "$_c3"

[ "$SG_STACKS_SOURCE" = "auto" ] \
    && ok  "config: unparseable JSON → source=auto" \
    || bad "config: unparseable JSON → source=auto" "got: $SG_STACKS_SOURCE"

case "$SG_STACKS_WARNINGS" in
    *"invalid JSON"*)
        ok  "config: unparseable JSON → warning emitted" ;;
    *)
        bad "config: unparseable JSON → warning emitted" "got: $SG_STACKS_WARNINGS" ;;
esac

# --------------------------------------------------------------------------- #
# 4. Explicit stacks → file; autodetect ignored even with go.mod present
# --------------------------------------------------------------------------- #

_c4="${CONFIG_WORK}/explicit-stacks"
mkdir -p "$_c4"
# go.mod is present so autodetect would produce "go"; the config says only "docker".
printf 'module example.com\n\ngo 1.23\n' > "${_c4}/go.mod"
printf '{"stacks":["docker"]}' > "${_c4}/.slopguard.json"
config_resolve_stacks "$_c4"

[ "$SG_STACKS_SOURCE" = "file" ] \
    && ok  "config: explicit stacks → source=file" \
    || bad "config: explicit stacks → source=file" "got: $SG_STACKS_SOURCE"

case " $SG_STACKS " in
    *" docker "*)
        ok  "config: explicit stacks → docker present" ;;
    *)
        bad "config: explicit stacks → docker present" "got: $SG_STACKS" ;;
esac

case " $SG_STACKS " in
    *" go "*)
        bad "config: explicit stacks → go absent (autodetect ignored)" "got: $SG_STACKS" ;;
    *)
        ok  "config: explicit stacks → go absent (autodetect ignored)" ;;
esac

# --------------------------------------------------------------------------- #
# 5. paths only → file-paths; declared list wins over what the subtree contains
# --------------------------------------------------------------------------- #

_c5="${CONFIG_WORK}/paths-only"
mkdir -p "${_c5}/backend"
printf 'module example.com\n\ngo 1.23\n' > "${_c5}/backend/go.mod"
printf '{"paths":{"backend":["ruby"]}}' > "${_c5}/.slopguard.json"
config_resolve_stacks "$_c5"

[ "$SG_STACKS_SOURCE" = "file-paths" ] \
    && ok  "config: paths only → source=file-paths" \
    || bad "config: paths only → source=file-paths" "got: $SG_STACKS_SOURCE"

case " $SG_STACKS " in
    *" ruby "*)
        ok  "config: paths only → declared tag applied" ;;
    *)
        bad "config: paths only → declared tag applied" "got: $SG_STACKS" ;;
esac

case " $SG_STACKS " in
    *" go "*)
        bad "config: paths only → subtree autodetection not consulted" "got: $SG_STACKS" ;;
    *)
        ok  "config: paths only → subtree autodetection not consulted" ;;
esac

_c5b="${CONFIG_WORK}/paths-undetectable"
mkdir -p "${_c5b}/services/api"
printf '{"paths":{"services/api":["java","docker"]}}' > "${_c5b}/.slopguard.json"
config_resolve_stacks "$_c5b"

case " $SG_STACKS " in
    *" java "*docker*|*" docker "*java*)
        ok  "config: paths → stacks declared for a manifest-free subtree" ;;
    *)
        bad "config: paths → stacks declared for a manifest-free subtree" "got: $SG_STACKS" ;;
esac

_c5c="${CONFIG_WORK}/paths-bad-value"
mkdir -p "${_c5c}/backend"
printf '{"paths":{"backend":"go"}}' > "${_c5c}/.slopguard.json"
config_resolve_stacks "$_c5c"

case "$SG_STACKS_WARNINGS" in
    *"must be an array"*)
        ok  "config: paths → non-array value warned and skipped" ;;
    *)
        bad "config: paths → non-array value warned and skipped" "got: $SG_STACKS_WARNINGS" ;;
esac

# --------------------------------------------------------------------------- #
# 6. Both stacks and paths → file; union
# --------------------------------------------------------------------------- #

_c6="${CONFIG_WORK}/both"
mkdir -p "${_c6}/backend"
printf 'module example.com\n\ngo 1.23\n' > "${_c6}/backend/go.mod"
printf '{"stacks":["docker"],"paths":{"backend":["go"]}}' > "${_c6}/.slopguard.json"
config_resolve_stacks "$_c6"

[ "$SG_STACKS_SOURCE" = "file" ] \
    && ok  "config: stacks+paths → source=file" \
    || bad "config: stacks+paths → source=file" "got: $SG_STACKS_SOURCE"

case " $SG_STACKS " in
    *" docker "*)
        ok  "config: stacks+paths → docker present (from stacks)" ;;
    *)
        bad "config: stacks+paths → docker present (from stacks)" "got: $SG_STACKS" ;;
esac

case " $SG_STACKS " in
    *" go "*)
        ok  "config: stacks+paths → go present (from paths)" ;;
    *)
        bad "config: stacks+paths → go present (from paths)" "got: $SG_STACKS" ;;
esac

# --------------------------------------------------------------------------- #
# 7. Unknown tag → dropped with warning; good tags survive
# --------------------------------------------------------------------------- #

_c7="${CONFIG_WORK}/unknown-tag"
mkdir -p "$_c7"
printf '{"stacks":["go","unknowntag_xyz_404"]}' > "${_c7}/.slopguard.json"
config_resolve_stacks "$_c7"

case " $SG_STACKS " in
    *" go "*)
        ok  "config: unknown tag → good tag survives" ;;
    *)
        bad "config: unknown tag → good tag survives" "got: $SG_STACKS" ;;
esac

case " $SG_STACKS " in
    *" unknowntag_xyz_404 "*)
        bad "config: unknown tag → bad tag dropped" "got: $SG_STACKS" ;;
    *)
        ok  "config: unknown tag → bad tag dropped" ;;
esac

case "$SG_STACKS_WARNINGS" in
    *"unknown stack"*"unknowntag_xyz_404"*)
        ok  "config: unknown tag → warning names the bad tag" ;;
    *)
        bad "config: unknown tag → warning names the bad tag" "got: $SG_STACKS_WARNINGS" ;;
esac

case "$SG_STACKS_WARNINGS" in
    *"valid:"*)
        ok  "config: unknown tag → warning lists valid tags" ;;
    *)
        bad "config: unknown tag → warning lists valid tags" "got: $SG_STACKS_WARNINGS" ;;
esac

# --------------------------------------------------------------------------- #
# 8. Nonexistent paths key → warned and skipped; source is file-paths
# --------------------------------------------------------------------------- #

_c8="${CONFIG_WORK}/missing-path"
mkdir -p "$_c8"
printf '{"paths":{"nonexistent-dir-xyz-9999":["go"]}}' > "${_c8}/.slopguard.json"
config_resolve_stacks "$_c8"

[ "$SG_STACKS_SOURCE" = "file-paths" ] \
    && ok  "config: nonexistent path → source=file-paths" \
    || bad "config: nonexistent path → source=file-paths" "got: $SG_STACKS_SOURCE"

case "$SG_STACKS_WARNINGS" in
    *"does not exist"*)
        ok  "config: nonexistent path → warning emitted" ;;
    *)
        bad "config: nonexistent path → warning emitted" "got: $SG_STACKS_WARNINGS" ;;
esac

# --------------------------------------------------------------------------- #
# 9. stacks: [] → file, zero stacks, warning
# --------------------------------------------------------------------------- #

_c9="${CONFIG_WORK}/empty-stacks"
mkdir -p "$_c9"
# go.mod present so autodetect would give "go"; explicit [] overrides.
printf 'module example.com\n\ngo 1.23\n' > "${_c9}/go.mod"
printf '{"stacks":[]}' > "${_c9}/.slopguard.json"
config_resolve_stacks "$_c9"

[ "$SG_STACKS_SOURCE" = "file" ] \
    && ok  "config: stacks:[] → source=file" \
    || bad "config: stacks:[] → source=file" "got: $SG_STACKS_SOURCE"

[ -z "$SG_STACKS" ] \
    && ok  "config: stacks:[] → zero stacks (autodetect not called)" \
    || bad "config: stacks:[] → zero stacks (autodetect not called)" "got: $SG_STACKS"

case "$SG_STACKS_WARNINGS" in
    *"no language layer"*)
        ok  "config: stacks:[] → no-language-layer warning" ;;
    *)
        bad "config: stacks:[] → no-language-layer warning" "got: $SG_STACKS_WARNINGS" ;;
esac

# --------------------------------------------------------------------------- #
# 10. implies applied: explicit helm → kubernetes added
# --------------------------------------------------------------------------- #

_c10="${CONFIG_WORK}/implies-helm"
mkdir -p "$_c10"
# No Chart.yaml — autodetect would NOT produce helm or kubernetes.
printf '{"stacks":["helm"]}' > "${_c10}/.slopguard.json"
config_resolve_stacks "$_c10"

case " $SG_STACKS " in
    *" helm "*)
        ok  "config: implies: helm in explicit list" ;;
    *)
        bad "config: implies: helm in explicit list" "got: $SG_STACKS" ;;
esac

case " $SG_STACKS " in
    *" kubernetes "*)
        ok  "config: implies: helm → kubernetes implied" ;;
    *)
        bad "config: implies: helm → kubernetes implied" "got: $SG_STACKS" ;;
esac

# --------------------------------------------------------------------------- #
# 11. requires NOT applied: explicit typescript survives without package.json
# --------------------------------------------------------------------------- #

_c11="${CONFIG_WORK}/requires-not-applied"
mkdir -p "$_c11"
# No package.json — autodetect would NOT detect typescript (requires node first).
# Explicit stacks list must honour typescript without requires gating.
printf '{"stacks":["typescript"]}' > "${_c11}/.slopguard.json"
config_resolve_stacks "$_c11"

case " $SG_STACKS " in
    *" typescript "*)
        ok  "config: requires not applied: explicit typescript survives without package.json" ;;
    *)
        bad "config: requires not applied: explicit typescript survives without package.json" \
            "got: $SG_STACKS" ;;
esac

# --------------------------------------------------------------------------- #

rm -rf "$CONFIG_WORK"
