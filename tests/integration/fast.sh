#!/usr/bin/env bash
# integration/fast.sh — real-tool integration tests for the fast tier.
#
# Covers: ruff, eslint-stack, hadolint, kube-linter, zizmor.
# Sourced by tests/tool-integration; helpers (it_ok/bad/skip/project/commit/
# modify/run/expect_ap/expect_silent) and counters (PASS/FAIL/SKIP) are
# defined there.  _IT_FIXTURES points at tests/fixtures/.
#
# Each tool block:
#   1. Creates a temp git project (it_project).
#   2. it_skip_unless_tool — skips the whole block if binary absent.
#   3. Commits a placeholder, then overwrites with the bad fixture (it_commit
#      + it_modify), so the Z2 diff filter sees the bad lines as changed.
#   4. Drives bin/slopguard post-write --tier=fast in advisory mode (it_run).
#   5. Asserts the mapped AP-* id appears (it_expect_ap).
#   6. Repeats steps 1–4 with the good fixture and asserts silence (it_expect_silent).
#
# shellcheck source=../tool-integration

# --------------------------------------------------------------------------- #
# ruff — Python fast-tier (S608 → AP-PY-SEC-001, security, blocker)
# --------------------------------------------------------------------------- #

it_project ruff-bad; _fast_proj="$_IT_CUR_PROJ"
if it_skip_unless_tool ruff; then
    it_commit "$_fast_proj" app.py 'x = 1'
    it_modify "$_fast_proj" app.py \
        "$(cat "${_IT_FIXTURES}/python/bad/sql_injection.py")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/app.py" fast)
    it_expect_ap "$_fast_out" AP-PY-SEC-001 \
        "ruff: SQL injection (bad fixture -> AP-PY-SEC-001)"

    it_project ruff-good; _fast_proj="$_IT_CUR_PROJ"
    it_skip_unless_tool ruff
    it_commit "$_fast_proj" app.py 'x = 99'
    it_modify "$_fast_proj" app.py \
        "$(cat "${_IT_FIXTURES}/python/good/sample.py")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/app.py" fast)
    it_expect_silent "$_fast_out" \
        "ruff: clean Python (good fixture -> silence)"
fi

# --------------------------------------------------------------------------- #
# eslint-stack — TypeScript fast-tier (no-eval → AP-TS-SEC-002, security, blocker)
# Binary name: eslint (lock_bin eslint-stack → eslint)
# --------------------------------------------------------------------------- #

it_project eslint-bad; _fast_proj="$_IT_CUR_PROJ"
if it_skip_unless_tool eslint-stack; then
    # ESLint needs package.json to detect ESM mode.
    it_commit "$_fast_proj" package.json '{"type":"module"}'
    it_commit "$_fast_proj" app.ts 'export {};'
    it_modify "$_fast_proj" app.ts \
        "$(cat "${_IT_FIXTURES}/ts/bad/eval.ts")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/app.ts" fast)
    it_expect_ap "$_fast_out" AP-TS-SEC-002 \
        "eslint: eval with user input (bad fixture -> AP-TS-SEC-002)"

    it_project eslint-good; _fast_proj="$_IT_CUR_PROJ"
    it_skip_unless_tool eslint-stack
    it_commit "$_fast_proj" package.json '{"type":"module"}'
    it_commit "$_fast_proj" app.tsx 'export {};'
    it_modify "$_fast_proj" app.tsx \
        "$(cat "${_IT_FIXTURES}/ts/good/sample.tsx")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/app.tsx" fast)
    it_expect_silent "$_fast_out" \
        "eslint: clean React component (good fixture -> silence)"
fi

# --------------------------------------------------------------------------- #
# hadolint — Dockerfile fast-tier (DL3007 → AP-DOCKER-001, security, error)
# File must be named exactly "Dockerfile" for the dispatch routing to fire.
# --------------------------------------------------------------------------- #

it_project hadolint-bad; _fast_proj="$_IT_CUR_PROJ"
if it_skip_unless_tool hadolint; then
    it_commit "$_fast_proj" Dockerfile 'FROM scratch'
    it_modify "$_fast_proj" Dockerfile \
        "$(cat "${_IT_FIXTURES}/docker/bad/latest_tag.Dockerfile")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/Dockerfile" fast)
    it_expect_ap "$_fast_out" AP-DOCKER-001 \
        "hadolint: FROM ubuntu:latest (bad fixture -> AP-DOCKER-001)"

    it_project hadolint-good; _fast_proj="$_IT_CUR_PROJ"
    it_skip_unless_tool hadolint
    it_commit "$_fast_proj" Dockerfile 'FROM scratch'
    it_modify "$_fast_proj" Dockerfile \
        "$(cat "${_IT_FIXTURES}/docker/good/Dockerfile")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/Dockerfile" fast)
    it_expect_silent "$_fast_out" \
        "hadolint: compliant Dockerfile (good fixture -> silence)"
fi

# --------------------------------------------------------------------------- #
# kube-linter — K8s manifest fast-tier (privileged-container → AP-K8S-001,
# security, blocker).
# kube-linter reports at line 0 (no line numbers in JSON), so the Z2 diff
# filter marks the finding as pre-existing-info; it still surfaces in advisory
# mode and carries the mapped AP-* id.
# --------------------------------------------------------------------------- #

it_project kube-bad; _fast_proj="$_IT_CUR_PROJ"
if it_skip_unless_tool kube-linter; then
    it_commit "$_fast_proj" deploy.yaml '# placeholder'
    it_modify "$_fast_proj" deploy.yaml \
        "$(cat "${_IT_FIXTURES}/kubernetes/bad/privileged.yaml")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/deploy.yaml" fast)
    it_expect_ap "$_fast_out" AP-K8S-001 \
        "kube-linter: privileged container (bad fixture -> AP-K8S-001)"

    it_project kube-good; _fast_proj="$_IT_CUR_PROJ"
    it_skip_unless_tool kube-linter
    it_commit "$_fast_proj" deploy.yaml '# placeholder'
    it_modify "$_fast_proj" deploy.yaml \
        "$(cat "${_IT_FIXTURES}/kubernetes/good/deployment.yaml")"
    _fast_out=$(it_run "$_fast_proj" "${_fast_proj}/deploy.yaml" fast)
    it_expect_silent "$_fast_out" \
        "kube-linter: compliant deployment (good fixture -> silence)"
fi

# --------------------------------------------------------------------------- #
# zizmor — GitHub Actions fast-tier (artipacked → AP-CI-005, security, error).
# File must be under .github/workflows/ for the dispatch path routing.
# The runner passes --offline so no network access is needed.
# actions/checkout@v4 without persist-credentials: false triggers artipacked
# (credential persistence through GitHub Actions artifacts) → AP-CI-005.
# Note: unpinned-uses only fires in --pedantic mode; the baseline config omits
# it, so the tag-pinned action fires artipacked, not AP-CI-001.
# --------------------------------------------------------------------------- #

it_project zizmor-bad; _fast_proj="$_IT_CUR_PROJ"
if it_skip_unless_tool zizmor; then
    it_commit "$_fast_proj" .github/workflows/ci.yml '# placeholder'
    it_modify "$_fast_proj" .github/workflows/ci.yml \
        "$(cat "${_IT_FIXTURES}/ci/bad/unpinned_action.yml")"
    _fast_out=$(it_run "$_fast_proj" \
        "${_fast_proj}/.github/workflows/ci.yml" fast)
    it_expect_ap "$_fast_out" AP-CI-005 \
        "zizmor: checkout without persist-credentials:false (bad fixture -> AP-CI-005)"

    it_project zizmor-good; _fast_proj="$_IT_CUR_PROJ"
    it_skip_unless_tool zizmor
    it_commit "$_fast_proj" .github/workflows/ci.yml '# placeholder'
    it_modify "$_fast_proj" .github/workflows/ci.yml \
        "$(cat "${_IT_FIXTURES}/ci/good/workflow.yml")"
    _fast_out=$(it_run "$_fast_proj" \
        "${_fast_proj}/.github/workflows/ci.yml" fast)
    it_expect_silent "$_fast_out" \
        "zizmor: SHA-pinned workflow (good fixture -> silence)"
fi
