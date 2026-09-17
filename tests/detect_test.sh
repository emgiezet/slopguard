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

# --- tier-2 language detection ---

mkdir -p "$DETECT_WORK/java"
touch "$DETECT_WORK/java/pom.xml"
assert_stacks java "$DETECT_WORK/java" java

# settings.gradle.kts is kotlin-only; build.gradle.kts is shared with java
mkdir -p "$DETECT_WORK/kotlin"
touch "$DETECT_WORK/kotlin/settings.gradle.kts"
assert_stacks kotlin "$DETECT_WORK/kotlin" kotlin

# *.sln glob at root is unambiguous for C#
mkdir -p "$DETECT_WORK/csharp"
touch "$DETECT_WORK/csharp/MyApp.sln"
assert_stacks csharp "$DETECT_WORK/csharp" csharp

mkdir -p "$DETECT_WORK/ruby"
touch "$DETECT_WORK/ruby/Gemfile"
assert_stacks ruby "$DETECT_WORK/ruby" ruby

mkdir -p "$DETECT_WORK/rust"
touch "$DETECT_WORK/rust/Cargo.toml"
assert_stacks rust "$DETECT_WORK/rust" rust

# --- requires gating ---

# tsconfig.json without package.json must not yield node or typescript
mkdir -p "$DETECT_WORK/ts-only"
touch "$DETECT_WORK/ts-only/tsconfig.json"
_sg_actual="$(detect_stacks "$DETECT_WORK/ts-only")"
case " $_sg_actual " in
    *" node "*|*" typescript "*)
        bad "detect: requires-gate typescript" "unexpected stacks in [${_sg_actual:-<empty>}]" ;;
    *) ok "detect: requires-gate typescript" ;;
esac

# artisan without composer.json must not yield php or laravel
mkdir -p "$DETECT_WORK/artisan-only"
touch "$DETECT_WORK/artisan-only/artisan"
_sg_actual="$(detect_stacks "$DETECT_WORK/artisan-only")"
case " $_sg_actual " in
    *" php "*|*" laravel "*)
        bad "detect: requires-gate laravel" "unexpected stacks in [${_sg_actual:-<empty>}]" ;;
    *) ok "detect: requires-gate laravel" ;;
esac

# --- stack_tier ---

_sg_tier="$(stack_tier go)"
[ "$_sg_tier" = "1" ] \
    && ok "stack_tier: go is tier 1" \
    || bad "stack_tier: go is tier 1" "got [${_sg_tier:-<empty>}]"

_sg_tier="$(stack_tier ruby)"
[ "$_sg_tier" = "2" ] \
    && ok "stack_tier: ruby is tier 2" \
    || bad "stack_tier: ruby is tier 2" "got [${_sg_tier:-<empty>}]"

# --- stack_known ---

stack_known "go" \
    && ok "stack_known: go is known" \
    || bad "stack_known: go is known" "returned non-zero"

stack_known "notastack" \
    && bad "stack_known: notastack rejected" "returned 0 for unknown tag" \
    || ok "stack_known: notastack rejected"

# --- stacks_all: all five tier-2 tags present ---

_sg_all="$(stacks_all)"
for _sg_t2 in java kotlin csharp ruby rust; do
    case " $_sg_all " in
        *" $_sg_t2 "*) ok "stacks_all: contains $_sg_t2" ;;
        *) bad "stacks_all: contains $_sg_t2" "missing from [${_sg_all:-<empty>}]" ;;
    esac
done

rm -rf "$DETECT_WORK"
