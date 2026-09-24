#!/usr/bin/env bash
# tests/adopt_test.sh — tests for slopguard adopt-config subcommand.
#
# Standalone: cd plugins/slop-guard && bash tests/adopt_test.sh
# Does NOT source run-tests counters; ok()/bad() defined locally.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

_TEST_DATA="${TMPDIR:-/tmp}/slop-guard-adopt-test-$$"
export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
export CLAUDE_PLUGIN_DATA="${_TEST_DATA}"
SLOPGUARD="${PLUGIN_ROOT}/bin/slopguard"

PASS=0; FAIL=0
ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s: %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

WORK="${TMPDIR:-/tmp}/slop-guard-adopt-work-$$"
mkdir -p "${WORK}" "${_TEST_DATA}"

_cleanup() { rm -rf "${WORK}" "${_TEST_DATA}"; }
trap '_cleanup' EXIT INT TERM

printf 'adopt-config tests\n\n'

# --------------------------------------------------------------------------- #
# 1. adopt-config with no argument: lists tools without project configs
# --------------------------------------------------------------------------- #

_clean="${WORK}/clean-project"
mkdir -p "${_clean}"

_list_out="$(CLAUDE_PROJECT_DIR="${_clean}" "${SLOPGUARD}" adopt-config 2>/dev/null)"

# ruff should appear (no project config in clean project)
printf '%s\n' "${_list_out}" | grep -q 'ruff' \
    && ok  "list: ruff appears for clean project" \
    || bad "list: ruff appears for clean project" "${_list_out}"

# golangci-lint should appear
printf '%s\n' "${_list_out}" | grep -q 'golangci-lint' \
    && ok  "list: golangci-lint appears for clean project" \
    || bad "list: golangci-lint appears for clean project" "${_list_out}"

# jq has no config concept — must NOT appear
printf '%s\n' "${_list_out}" | grep -q '^  jq ' \
    && bad "list: jq must not appear (no config concept)" "${_list_out}" \
    || ok  "list: jq correctly absent (no config concept)"

# the tool named shellcheck has no config concept — must NOT appear in listing
printf '%s\n' "${_list_out}" | grep -q '^  shellcheck ' \
    && bad "list: shellcheck must not appear (no config concept)" "${_list_out}" \
    || ok  "list: shellcheck correctly absent (no config concept)"

# baseline file paths must be mentioned in the listing
printf '%s\n' "${_list_out}" | grep -q 'ruff.toml' \
    && ok  "list: baseline filename shown for ruff" \
    || bad "list: baseline filename shown for ruff" "${_list_out}"

# --------------------------------------------------------------------------- #
# 2. adopt-config with project config present: listed tool absent
# --------------------------------------------------------------------------- #

_ruff_proj="${WORK}/ruff-project"
mkdir -p "${_ruff_proj}"
printf '[tool.ruff]\n' > "${_ruff_proj}/pyproject.toml"

_list_ruff="$(CLAUDE_PROJECT_DIR="${_ruff_proj}" "${SLOPGUARD}" adopt-config 2>/dev/null)"
printf '%s\n' "${_list_ruff}" | grep -qE '^\s+ruff\s' \
    && bad "list: ruff must not appear when pyproject.toml has [tool.ruff]" "${_list_ruff}" \
    || ok  "list: ruff absent from listing when pyproject.toml has [tool.ruff]"

_ruff_proj2="${WORK}/ruff-project2"
mkdir -p "${_ruff_proj2}"
printf '# ruff config\n' > "${_ruff_proj2}/ruff.toml"

_list_ruff2="$(CLAUDE_PROJECT_DIR="${_ruff_proj2}" "${SLOPGUARD}" adopt-config 2>/dev/null)"
printf '%s\n' "${_list_ruff2}" | grep -qE '^\s+ruff\s' \
    && bad "list: ruff must not appear when ruff.toml exists" "${_list_ruff2}" \
    || ok  "list: ruff absent from listing when ruff.toml present"

# --------------------------------------------------------------------------- #
# 3. adopt-config <tool>: successful copy
# --------------------------------------------------------------------------- #

_dest_proj="${WORK}/dest-project"
mkdir -p "${_dest_proj}"

_adopt_out="$(CLAUDE_PROJECT_DIR="${_dest_proj}" "${SLOPGUARD}" adopt-config ruff 2>/dev/null)"
_expected_dest="${_dest_proj}/ruff.toml"

[ -f "${_expected_dest}" ] \
    && ok  "adopt ruff: destination file created" \
    || bad "adopt ruff: destination file created" "not found: ${_expected_dest}"

# Output must include the destination path
printf '%s\n' "${_adopt_out}" | grep -q "${_expected_dest}" \
    && ok  "adopt ruff: output includes destination path" \
    || bad "adopt ruff: output includes destination path" "${_adopt_out}"

# Output must mention write-protection
printf '%s\n' "${_adopt_out}" | grep -qi 'write-protected\|ask required' \
    && ok  "adopt ruff: output mentions write-protection" \
    || bad "adopt ruff: output mentions write-protection" "${_adopt_out}"

# --------------------------------------------------------------------------- #
# 4. Adopted file is byte-identical to the baseline
# --------------------------------------------------------------------------- #

_baseline_ruff="${PLUGIN_ROOT}/configs/baseline/ruff.toml"
if [ -f "${_baseline_ruff}" ] && [ -f "${_expected_dest}" ]; then
    if cmp -s "${_baseline_ruff}" "${_expected_dest}"; then
        ok  "adopt ruff: copied file is byte-identical to baseline"
    else
        bad "adopt ruff: copied file is byte-identical to baseline" \
            "files differ: baseline=${_baseline_ruff} copy=${_expected_dest}"
    fi
else
    bad "adopt ruff: byte-identity check" \
        "missing: baseline=${_baseline_ruff} or dest=${_expected_dest}"
fi

# --------------------------------------------------------------------------- #
# 5. Second run refuses (existing project config)
# --------------------------------------------------------------------------- #

_adopt_err="$(CLAUDE_PROJECT_DIR="${_dest_proj}" "${SLOPGUARD}" adopt-config ruff 2>&1)"
_adopt_exit=$?

[ "${_adopt_exit}" -ne 0 ] \
    && ok  "adopt ruff: second run exits non-zero" \
    || bad "adopt ruff: second run exits non-zero" "exit code was 0"

printf '%s\n' "${_adopt_err}" | grep -qi 'already exists\|project config' \
    && ok  "adopt ruff: second run names the existing file" \
    || bad "adopt ruff: second run names the existing file" "${_adopt_err}"

# After the refusal the original file must still exist and be unchanged
if [ -f "${_expected_dest}" ]; then
    if cmp -s "${_baseline_ruff}" "${_expected_dest}"; then
        ok  "adopt ruff: original file unmodified after refusal"
    else
        bad "adopt ruff: original file unmodified after refusal" "file content changed"
    fi
else
    bad "adopt ruff: original file still present after refusal" "file was removed"
fi

# --------------------------------------------------------------------------- #
# 6. adopt-config .eslintrc refusal: destination already exists
# --------------------------------------------------------------------------- #

_es_proj="${WORK}/eslint-project"
mkdir -p "${_es_proj}"
printf '{}\n' > "${_es_proj}/.eslintrc.json"   # recognised by tool_config_path

_es_err="$(CLAUDE_PROJECT_DIR="${_es_proj}" "${SLOPGUARD}" adopt-config eslint-stack 2>&1)"
_es_exit=$?

[ "${_es_exit}" -ne 0 ] \
    && ok  "adopt eslint-stack: refuses when project config exists" \
    || bad "adopt eslint-stack: refuses when project config exists" "exit 0 — should fail"

printf '%s\n' "${_es_err}" | grep -qi 'already exists\|project config' \
    && ok  "adopt eslint-stack: refusal message mentions existing config" \
    || bad "adopt eslint-stack: refusal message mentions existing config" "${_es_err}"

# --------------------------------------------------------------------------- #
# 7. adopt-config for a tool with no single-file config (opengrep → directory)
# --------------------------------------------------------------------------- #

_og_proj="${WORK}/og-project"
mkdir -p "${_og_proj}"

_og_err="$(CLAUDE_PROJECT_DIR="${_og_proj}" "${SLOPGUARD}" adopt-config opengrep 2>&1)"
_og_exit=$?

[ "${_og_exit}" -ne 0 ] \
    && ok  "adopt opengrep: exits non-zero (directory-based baseline)" \
    || bad "adopt opengrep: exits non-zero (directory-based baseline)" "exit 0 — should fail"

# --------------------------------------------------------------------------- #
# 8. adopt-config for an unknown tool
# --------------------------------------------------------------------------- #

_unk_err="$(CLAUDE_PROJECT_DIR="${_dest_proj}" "${SLOPGUARD}" adopt-config no-such-tool 2>&1)"
_unk_exit=$?

[ "${_unk_exit}" -ne 0 ] \
    && ok  "adopt unknown tool: exits non-zero" \
    || bad "adopt unknown tool: exits non-zero" "exit 0 — should fail"

# --------------------------------------------------------------------------- #
# 9. golangci-lint: successful copy to primary destination
# --------------------------------------------------------------------------- #

_go_proj="${WORK}/go-project"
mkdir -p "${_go_proj}"

_go_adopt_out="$(CLAUDE_PROJECT_DIR="${_go_proj}" "${SLOPGUARD}" adopt-config golangci-lint 2>/dev/null)"
_go_dest="${_go_proj}/.golangci.yml"

[ -f "${_go_dest}" ] \
    && ok  "adopt golangci-lint: destination .golangci.yml created" \
    || bad "adopt golangci-lint: destination .golangci.yml created" "not found: ${_go_dest}"

_baseline_go="${PLUGIN_ROOT}/configs/baseline/.golangci.yml"
if [ -f "${_baseline_go}" ] && [ -f "${_go_dest}" ]; then
    cmp -s "${_baseline_go}" "${_go_dest}" \
        && ok  "adopt golangci-lint: byte-identical to baseline" \
        || bad "adopt golangci-lint: byte-identical to baseline" "files differ"
else
    bad "adopt golangci-lint: byte-identity check" "file missing"
fi

# --------------------------------------------------------------------------- #
# 11. jscpd: listing, adopt, second-run refusal, absent after adopt
# --------------------------------------------------------------------------- #

_jscpd_clean="${WORK}/jscpd-clean"
mkdir -p "${_jscpd_clean}"

_jscpd_list_out="$(CLAUDE_PROJECT_DIR="${_jscpd_clean}" "${SLOPGUARD}" adopt-config 2>/dev/null)"

# jscpd should appear for a clean project (no .jscpd.json present)
printf '%s\n' "${_jscpd_list_out}" | grep -q 'jscpd' \
    && ok  "list: jscpd appears for clean project" \
    || bad "list: jscpd appears for clean project" "${_jscpd_list_out}"

# baseline filename must be named in the listing
printf '%s\n' "${_jscpd_list_out}" | grep -q '\.jscpd\.json' \
    && ok  "list: baseline filename .jscpd.json shown for jscpd" \
    || bad "list: baseline filename .jscpd.json shown for jscpd" "${_jscpd_list_out}"

# Adopt jscpd into the clean project
_jscpd_adopt_out="$(CLAUDE_PROJECT_DIR="${_jscpd_clean}" "${SLOPGUARD}" adopt-config jscpd 2>/dev/null)"
_jscpd_dest="${_jscpd_clean}/.jscpd.json"

[ -f "${_jscpd_dest}" ] \
    && ok  "adopt jscpd: .jscpd.json created in project" \
    || bad "adopt jscpd: .jscpd.json created in project" "not found: ${_jscpd_dest}"

_baseline_jscpd="${PLUGIN_ROOT}/configs/baseline/.jscpd.json"
if [ -f "${_baseline_jscpd}" ] && [ -f "${_jscpd_dest}" ]; then
    cmp -s "${_baseline_jscpd}" "${_jscpd_dest}" \
        && ok  "adopt jscpd: copied file is byte-identical to baseline" \
        || bad "adopt jscpd: copied file is byte-identical to baseline" "files differ"
else
    bad "adopt jscpd: byte-identity check" \
        "missing: baseline=${_baseline_jscpd} or dest=${_jscpd_dest}"
fi

# Second run must exit non-zero and leave the file unmodified
_jscpd_adopt2_err="$(CLAUDE_PROJECT_DIR="${_jscpd_clean}" "${SLOPGUARD}" adopt-config jscpd 2>&1)"
_jscpd_adopt2_exit=$?

[ "${_jscpd_adopt2_exit}" -ne 0 ] \
    && ok  "adopt jscpd: second run exits non-zero" \
    || bad "adopt jscpd: second run exits non-zero" "exit code was 0"

if [ -f "${_baseline_jscpd}" ] && [ -f "${_jscpd_dest}" ]; then
    cmp -s "${_baseline_jscpd}" "${_jscpd_dest}" \
        && ok  "adopt jscpd: file unmodified after second-run refusal" \
        || bad "adopt jscpd: file unmodified after second-run refusal" "file content changed"
else
    bad "adopt jscpd: file still present after second-run refusal" "file was removed"
fi

# jscpd must be absent from the listing once .jscpd.json is present
_jscpd_list2="$(CLAUDE_PROJECT_DIR="${_jscpd_clean}" "${SLOPGUARD}" adopt-config 2>/dev/null)"
printf '%s\n' "${_jscpd_list2}" | grep -qE '^\s+jscpd\s' \
    && bad "list: jscpd must not appear when .jscpd.json exists" "${_jscpd_list2}" \
    || ok  "list: jscpd absent from listing when .jscpd.json present"

# --------------------------------------------------------------------------- #
# 10. Listing shows "All tools have project configs" when all have configs
# --------------------------------------------------------------------------- #

_all_proj="${WORK}/all-configured"
mkdir -p "${_all_proj}"
# Create a config file for every adoptable tool.
printf '' > "${_all_proj}/.gitleaks.toml"
printf '' > "${_all_proj}/.checkov.yaml"
printf '' > "${_all_proj}/eslint.config.mjs"
printf '' > "${_all_proj}/.golangci.yml"
printf '' > "${_all_proj}/.hadolint.yaml"
printf '' > "${_all_proj}/.kube-linter.yaml"
printf '' > "${_all_proj}/phpstan.neon"
printf '' > "${_all_proj}/psalm.xml"
printf '' > "${_all_proj}/ruff.toml"
printf '' > "${_all_proj}/.tflint.hcl"
printf '' > "${_all_proj}/zizmor.yml"
printf '' > "${_all_proj}/.jscpd.json"
# opengrep: create a .semgrep.yml so tool_config_path recognises it as project
printf '' > "${_all_proj}/.semgrep.yml"

# Descriptor templates also count as adoptable, so adopt them too before
# asserting that nothing is left.
mkdir -p "${_all_proj}/.slopguard/tools"
for _tpl in "${PLUGIN_ROOT}"/configs/baseline/descriptors/*.yaml; do
    [ -f "${_tpl}" ] || continue
    cp "${_tpl}" "${_all_proj}/.slopguard/tools/${_tpl##*/}"
done

_all_out="$(CLAUDE_PROJECT_DIR="${_all_proj}" "${SLOPGUARD}" adopt-config 2>/dev/null)"
printf '%s\n' "${_all_out}" | grep -qi 'all tools have project configs\|nothing to adopt' \
    && ok  "list: reports all configured when every tool has a project config" \
    || bad "list: reports all configured" "${_all_out}"

# --------------------------------------------------------------------------- #
printf '\nadopt-config: project-local descriptors\n'
# --------------------------------------------------------------------------- #

_desc_proj="${WORK}/descriptors"
mkdir -p "${_desc_proj}"

_desc_list="$(CLAUDE_PROJECT_DIR="${_desc_proj}" "${SLOPGUARD}" adopt-config 2>/dev/null)"
printf '%s\n' "${_desc_list}" | grep -q 'mypy.*project-local descriptor' \
    && ok  "list: mypy offered as a project-local descriptor" \
    || bad "list: mypy offered as a project-local descriptor" "${_desc_list}"

_desc_out="$(CLAUDE_PROJECT_DIR="${_desc_proj}" "${SLOPGUARD}" adopt-config mypy 2>&1)"
_desc_dest="${_desc_proj}/.slopguard/tools/mypy.yaml"
[ -f "${_desc_dest}" ] \
    && ok  "adopt mypy: descriptor written to .slopguard/tools" \
    || bad "adopt mypy: descriptor written to .slopguard/tools" "${_desc_out}"

cmp -s "${PLUGIN_ROOT}/configs/baseline/descriptors/mypy.yaml" "${_desc_dest}" \
    && ok  "adopt mypy: copied file is byte-identical to the template" \
    || bad "adopt mypy: copied file is byte-identical to the template" "differs"

printf '%s\n' "${_desc_out}" | grep -q 'installs nothing' \
    && ok  "adopt mypy: output states the plugin installs nothing for it" \
    || bad "adopt mypy: output states the plugin installs nothing for it" "${_desc_out}"

if CLAUDE_PROJECT_DIR="${_desc_proj}" "${SLOPGUARD}" adopt-config mypy >/dev/null 2>&1; then
    bad "adopt mypy: second run exits non-zero" "exit 0 on existing descriptor"
else
    ok "adopt mypy: second run exits non-zero"
fi

_desc_list2="$(CLAUDE_PROJECT_DIR="${_desc_proj}" "${SLOPGUARD}" adopt-config 2>/dev/null)"
if printf '%s\n' "${_desc_list2}" | grep -q 'mypy.*project-local descriptor'; then
    bad "list: adopted descriptor drops out of the listing" "${_desc_list2}"
else
    ok "list: adopted descriptor drops out of the listing"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
