#!/usr/bin/env bash
# detect_test.sh — sourced by tests/run-tests; ok()/bad() are pre-defined.

# shellcheck source=../lib/detect.sh
. "${PLUGIN_ROOT}/lib/detect.sh"

DETECT_WORK="${TMPDIR:-/tmp}/slopguard-detect-test-$$"
mkdir -p "$DETECT_WORK"

assert_stacks() {
    local label="$1" root="$2" expected="$3" actual stack missing=""
    actual="$(detect_stacks "$root")"
    for stack in $expected; do
        case " $actual " in *" $stack "*) ;; *) missing="${missing:+$missing }$stack" ;; esac
    done
    [ -z "$missing" ] \
        && ok "detect: $label" \
        || bad "detect: $label" "missing [$missing] from [$actual]"
}

mkdir -p "$DETECT_WORK/laravel"
printf '%s' '{"require":{"laravel/framework":"^11"}}' > "$DETECT_WORK/laravel/composer.json"
touch "$DETECT_WORK/laravel/artisan"
assert_stacks laravel "$DETECT_WORK/laravel" 'php laravel'

mkdir -p "$DETECT_WORK/symfony"
printf '%s' '{"require":{"symfony/framework-bundle":"^7"}}' > "$DETECT_WORK/symfony/composer.json"
assert_stacks symfony "$DETECT_WORK/symfony" 'php symfony'

mkdir -p "$DETECT_WORK/go"
touch "$DETECT_WORK/go/go.mod"
assert_stacks go "$DETECT_WORK/go" go

mkdir -p "$DETECT_WORK/python"
touch "$DETECT_WORK/python/uv.lock"
assert_stacks python "$DETECT_WORK/python" python

mkdir -p "$DETECT_WORK/react"
printf '%s' '{"dependencies":{"react":"latest","vite":"latest"}}' > "$DETECT_WORK/react/package.json"
touch "$DETECT_WORK/react/tsconfig.json"
assert_stacks react "$DETECT_WORK/react" 'node typescript react vite'

mkdir -p "$DETECT_WORK/express"
printf '%s' '{"dependencies":{"express":"latest"}}' > "$DETECT_WORK/express/package.json"
assert_stacks express "$DETECT_WORK/express" 'node express'

mkdir -p "$DETECT_WORK/helm"
touch "$DETECT_WORK/helm/Chart.yaml"
assert_stacks helm "$DETECT_WORK/helm" 'helm kubernetes'

mkdir -p "$DETECT_WORK/terraform"
touch "$DETECT_WORK/terraform/main.tf"
assert_stacks terraform "$DETECT_WORK/terraform" terraform

rm -rf "$DETECT_WORK"
