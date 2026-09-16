#!/usr/bin/env bash
# lib/detect.sh — network-free project stack detection.

_detect_add() {
    case " $1 " in *" $2 "*) printf '%s' "$1" ;; *) printf '%s%s' "${1:+$1 }" "$2" ;; esac
}

detect_stacks() {
    local root="${1:-.}" stacks="" file

    if [ -f "$root/composer.json" ]; then
        stacks="$(_detect_add "$stacks" php)"
        if [ -f "$root/artisan" ] || grep -qF '"laravel/framework"' "$root/composer.json" 2>/dev/null; then
            stacks="$(_detect_add "$stacks" laravel)"
        fi
        grep -qF '"symfony/framework-bundle"' "$root/composer.json" 2>/dev/null \
            && stacks="$(_detect_add "$stacks" symfony)"
        grep -qF '"doctrine/orm"' "$root/composer.json" 2>/dev/null \
            && stacks="$(_detect_add "$stacks" doctrine)"
    fi

    [ -f "$root/go.mod" ] && stacks="$(_detect_add "$stacks" go)"

    if [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.cfg" ] \
        || [ -f "$root/uv.lock" ] || [ -f "$root/poetry.lock" ]; then
        stacks="$(_detect_add "$stacks" python)"
    else
        for file in "$root"/requirements*.txt; do
            if [ -f "$file" ]; then stacks="$(_detect_add "$stacks" python)"; break; fi
        done
    fi

    if [ -f "$root/package.json" ]; then
        stacks="$(_detect_add "$stacks" node)"
        [ -f "$root/tsconfig.json" ] && stacks="$(_detect_add "$stacks" typescript)"
        grep -qF '"react"' "$root/package.json" 2>/dev/null \
            && stacks="$(_detect_add "$stacks" react)"
        grep -qF '"vite"' "$root/package.json" 2>/dev/null \
            && stacks="$(_detect_add "$stacks" vite)"
        grep -qF '"express"' "$root/package.json" 2>/dev/null \
            && stacks="$(_detect_add "$stacks" express)"
    fi

    for file in "$root"/*.tf; do
        if [ -f "$file" ]; then stacks="$(_detect_add "$stacks" terraform)"; break; fi
    done
    if [ -f "$root/Chart.yaml" ]; then
        stacks="$(_detect_add "$stacks" helm)"
        stacks="$(_detect_add "$stacks" kubernetes)"
    elif [ -f "$root/kustomization.yaml" ] || [ -f "$root/kustomization.yml" ]; then
        stacks="$(_detect_add "$stacks" kubernetes)"
    fi
    if [ -f "$root/Dockerfile" ] || [ -f "$root/docker-compose.yml" ] || [ -f "$root/compose.yaml" ]; then
        stacks="$(_detect_add "$stacks" docker)"
    fi
    [ -d "$root/.github/workflows" ] && stacks="$(_detect_add "$stacks" github-actions)"
    [ -f "$root/.gitlab-ci.yml" ] && stacks="$(_detect_add "$stacks" gitlab-ci)"

    printf '%s\n' "$stacks"
}
