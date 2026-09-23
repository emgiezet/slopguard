#!/usr/bin/env bash
# omp_adapter_test.sh — sourced by tests/run-tests.
#
# Runs omp_adapter_test.mjs under node --test and maps each TAP pass/fail line
# to an ok()/bad() call so the assertions appear in the run-tests counter.
# ok() and bad() are pre-defined by run-tests.

_OMP_MJS="${TESTS_DIR}/omp_adapter_test.mjs"

if ! command -v node >/dev/null 2>&1; then
    bad "omp-adapter: node runtime" "node not found on PATH"
else
    # Run the node test suite; capture full output (stdout + stderr) in one stream
    # so TAP lines and diagnostic lines arrive together for inspection on failure.
    _omp_tap_output="$(node --test --test-reporter=tap "${_OMP_MJS}" 2>&1)"
    _omp_exit="$?"

    # Parse TAP lines: "ok N - description" and "not ok N - description".
    # Subtests are indented (spaces before ok/not ok) — skip them; only root-level
    # lines drive the ok()/bad() counters.
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^ok\ [0-9]+\ -\ (.+)$ ]]; then
            ok "omp-adapter: ${BASH_REMATCH[1]}"
        elif [[ "$_line" =~ ^not\ ok\ [0-9]+\ -\ (.+)$ ]]; then
            bad "omp-adapter: ${BASH_REMATCH[1]}" "node test failed — see output above"
        fi
    done <<< "$_omp_tap_output"

    # If node exited non-zero but no individual test lines were parsed (e.g. a
    # syntax error prevented the suite from loading), emit one aggregate failure.
    if [ "$_omp_exit" -ne 0 ]; then
        _omp_parsed=0
        while IFS= read -r _line; do
            [[ "$_line" =~ ^(ok|not\ ok)\ [0-9]+ ]] && _omp_parsed=1 && break
        done <<< "$_omp_tap_output"
        if [ "$_omp_parsed" -eq 0 ]; then
            bad "omp-adapter: suite load" "node exited ${_omp_exit}; ${_omp_tap_output}"
        fi
    fi

    unset _omp_tap_output _omp_exit _omp_parsed _line
fi

unset _OMP_MJS
