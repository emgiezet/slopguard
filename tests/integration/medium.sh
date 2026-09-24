#!/usr/bin/env bash
# tests/integration/medium.sh — medium-tier integration tests.
# Sourced by tests/tool-integration after the helper API (it_*) is defined.
#
# Coverage (bad fixture → mapped AP-id, good fixture → silence):
#   phpstan       — missingType.return → AP-PHP-MAINT-003   (untracked; CONFIG_SOURCE=full)
#   golangci-lint — gosec G201 (fmt.Sprintf SQL) → AP-GO-SEC-002  (tracked+modified)
#   tflint        — terraform_required_version → AP-TF-MAINT-003  (untracked; CONFIG_SOURCE=full)
#   checkov (M)   — CKV2_AWS_62 (S3 event notifications) → AP-TF-SEC-018  (untracked)
#
# Design notes
# ------------
# phpstan:       Untracked PHP file → is_untracked=1; dispatcher applies --level=max (§6.1).
#                All phpstan rules are maintainability; CONFIG_SOURCE=full is required for
#                findings to pass the overlay filter.
# golangci-lint: The dispatcher passes --new-from-rev=HEAD for tracked files (Z2 native).
#                We commit the clean version, then overwrite it (unstaged) so the bad code
#                lands on the changed lines that golangci-lint reports.  gosec G201 is
#                security → passes overlay without needing CONFIG_SOURCE=full.
# tflint:        Untracked .tf file; terraform_required_version (core plugin, no AWS plugin
#                needed) fires when the terraform{} block is absent.  maintainability →
#                CONFIG_SOURCE=full required.  A project-local .tflint.hcl that omits the
#                AWS plugin avoids the plugin-download failure on offline machines.
# checkov:       Untracked .tf file; CKV_AWS_57 does not fire in checkov 3.3.16 (check
#                was reorganised).  CKV2_AWS_62 (S3 event notifications) fires on any
#                aws_s3_bucket resource → AP-TF-SEC-018.  Security → passes overlay.
#                Medium-tier checkov runs per-file (-f), not per-directory.

# Ensure phpstan can write its tmp cache even when SLOPGUARD_CACHE_DIR is absent.
: "${SLOPGUARD_CACHE_DIR:=${_IT_WORK}/cache}"
export SLOPGUARD_CACHE_DIR
mkdir -p "${SLOPGUARD_CACHE_DIR}/phpstan"

# =========================================================================== #
# 1. phpstan — missingType.return → AP-PHP-MAINT-003
# =========================================================================== #

it_project "phpstan-bad"
_it_med_php_bad="$_IT_CUR_PROJ"
if it_skip_unless_tool phpstan; then
    # Untracked file: judged whole; --level=max applied; no Z2 line filter.
    cp "${_IT_FIXTURES}/php/bad/AP-PHP-MAINT-003.php" "${_it_med_php_bad}/Bad.php"

    _it_med_php_out="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=full \
        it_run "${_it_med_php_bad}" "${_it_med_php_bad}/Bad.php" medium)"
    it_expect_ap "$_it_med_php_out" "AP-PHP-MAINT-003" \
        "phpstan: missingType.return → AP-PHP-MAINT-003"

    it_project "phpstan-good"
    _it_med_php_good="$_IT_CUR_PROJ"
    it_skip_unless_tool phpstan  # re-symlinks phpstan into new project; never skips here
    cp "${_IT_FIXTURES}/php/good/AP-PHP-MAINT-003.php" "${_it_med_php_good}/Good.php"

    _it_med_php_good_out="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=full \
        it_run "${_it_med_php_good}" "${_it_med_php_good}/Good.php" medium)"
    it_expect_silent "$_it_med_php_good_out" \
        "phpstan: fully-typed function produces no finding"
fi

# =========================================================================== #
# 2. golangci-lint — gosec G201 (fmt.Sprintf SQL) → AP-GO-SEC-002
# =========================================================================== #

it_project "golangci-lint-bad"
_it_med_go_bad="$_IT_CUR_PROJ"
if it_skip_unless_tool golangci-lint; then
    # Version guard: golangci-lint v1.x uses --out-format=json but the dispatcher
    # uses --output.json.path=stdout (v2 flag).  v1.x exits 3 (unknown flag) and
    # the dispatcher fails-open — no finding is emitted.  Skip explicitly.
    _gl_ver="$("${_it_med_go_bad}/vendor/bin/golangci-lint" version 2>/dev/null || true)"
    case "$_gl_ver" in
        *"v1."*)
            printf '  skip  golangci-lint: v1.x in PATH; dispatcher requires v2 (slopguard doctor --install)\n'
            SKIP=$((SKIP + 1))
            ;;
        *)
            # v2+ installed: exercise the tracked+modified path (--new-from-rev=HEAD).
            # Minimal Go module; must exist before any commit so golangci-lint can resolve the pkg.
            printf 'module slopguardtest\n\ngo 1.21\n' > "${_it_med_go_bad}/go.mod"
            git -C "${_it_med_go_bad}" add go.mod 2>/dev/null
            git -C "${_it_med_go_bad}" commit -q -m "add go.mod" 2>/dev/null

            # Commit the safe version so the file is tracked at HEAD.
            _it_med_go_good_content="$(cat "${_IT_FIXTURES}/go/good/AP-GO-SEC-002.go")"
            it_commit "${_it_med_go_bad}" "main.go" "$_it_med_go_good_content"

            # Overwrite with the bad version (unstaged diff); golangci-lint --new-from-rev=HEAD
            # restricts findings to changed lines, which is where G201 now lives.
            _it_med_go_bad_content="$(cat "${_IT_FIXTURES}/go/bad/AP-GO-SEC-002.go")"
            it_modify "${_it_med_go_bad}" "main.go" "$_it_med_go_bad_content"

            _it_med_go_out="$(it_run "${_it_med_go_bad}" "${_it_med_go_bad}/main.go" medium)"
            it_expect_ap "$_it_med_go_out" "AP-GO-SEC-002" \
                "golangci-lint: gosec G201 (fmt.Sprintf SQL) → AP-GO-SEC-002"

            # Good: fresh project with the clean file as untracked (no --new-from-rev; whole-package scan).
            it_project "golangci-lint-good"
            _it_med_go_good_proj="$_IT_CUR_PROJ"
            it_skip_unless_tool golangci-lint  # re-symlinks into new project; never skips here

            printf 'module slopguardgood\n\ngo 1.21\n' > "${_it_med_go_good_proj}/go.mod"
            git -C "${_it_med_go_good_proj}" add go.mod 2>/dev/null
            git -C "${_it_med_go_good_proj}" commit -q -m "add go.mod" 2>/dev/null
            cp "${_IT_FIXTURES}/go/good/AP-GO-SEC-002.go" "${_it_med_go_good_proj}/main.go"

            _it_med_go_good_out="$(it_run "${_it_med_go_good_proj}" "${_it_med_go_good_proj}/main.go" medium)"
            it_expect_silent "$_it_med_go_good_out" \
                "golangci-lint: parameterised query produces no finding"
            ;;
    esac
fi

# =========================================================================== #
# 3. tflint — terraform_required_version → AP-TF-MAINT-003
# =========================================================================== #
# A project-local .tflint.hcl that uses only the built-in terraform plugin
# is created so the test never requires the AWS plugin (which needs a separate
# plugin-dir install and would cause tflint to exit 2 if absent).

it_project "tflint-bad"
_it_med_tf_bad="$_IT_CUR_PROJ"
if it_skip_unless_tool tflint; then
    # Minimal tflint config: terraform plugin only (no AWS plugin dependency).
    cat > "${_it_med_tf_bad}/.tflint.hcl" <<'ENDHCL'
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
ENDHCL
    # Untracked .tf file with no terraform{} block → terraform_required_version fires.
    cp "${_IT_FIXTURES}/terraform/bad/main.tf" "${_it_med_tf_bad}/main.tf"

    _it_med_tf_out="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=full \
        it_run "${_it_med_tf_bad}" "${_it_med_tf_bad}/main.tf" medium)"
    it_expect_ap "$_it_med_tf_out" "AP-TF-MAINT-003" \
        "tflint: missing required_version → AP-TF-MAINT-003"

    it_project "tflint-good"
    _it_med_tf_good="$_IT_CUR_PROJ"
    it_skip_unless_tool tflint  # re-symlinks; never skips here

    cat > "${_it_med_tf_good}/.tflint.hcl" <<'ENDHCL'
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
ENDHCL
    # Good fixture already has required_version >= 1.5 and no resources.
    cp "${_IT_FIXTURES}/terraform/good/main.tf" "${_it_med_tf_good}/main.tf"

    _it_med_tf_good_out="$(CLAUDE_PLUGIN_OPTION_CONFIG_SOURCE=full \
        it_run "${_it_med_tf_good}" "${_it_med_tf_good}/main.tf" medium)"
    it_expect_silent "$_it_med_tf_good_out" \
        "tflint: versioned module produces no finding"
fi

# =========================================================================== #
# 4. checkov (single-file, tier M) — CKV2_AWS_62 (S3 event notifications) → AP-TF-SEC-018
# =========================================================================== #
# Medium-tier checkov runs per-file (-f); the stop-gate runs per-dir (-d).
# CKV_AWS_57 does not fire in checkov 3.3.16 on the minimal aws_s3_bucket resource
# (the check was reorganised in the v3 series).  CKV2_AWS_62 fires on any S3 bucket
# without event notifications configured → AP-TF-SEC-018 (security, warn).

it_project "checkov-m-bad"
_it_med_ckv_bad="$_IT_CUR_PROJ"
if it_skip_unless_tool checkov; then
    cp "${_IT_FIXTURES}/terraform/bad/main.tf" "${_it_med_ckv_bad}/main.tf"

    _it_med_ckv_out="$(it_run "${_it_med_ckv_bad}" "${_it_med_ckv_bad}/main.tf" medium)"
    it_expect_ap "$_it_med_ckv_out" "AP-TF-SEC-018" \
        "checkov (M): S3 without event notifications → AP-TF-SEC-018"

    it_project "checkov-m-good"
    _it_med_ckv_good="$_IT_CUR_PROJ"
    it_skip_unless_tool checkov  # re-symlinks; never skips here

    cp "${_IT_FIXTURES}/terraform/good/main.tf" "${_it_med_ckv_good}/main.tf"

    _it_med_ckv_good_out="$(it_run "${_it_med_ckv_good}" "${_it_med_ckv_good}/main.tf" medium)"
    it_expect_silent "$_it_med_ckv_good_out" \
        "checkov (M): compliant TF produces no finding"
fi
