#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")" && pwd)

framework_commands=(
    awk
    curl
    fakeroot
    find
    grep
    install
    md5sum
    python3
    readelf
    sed
    sha256sum
    sort
    stat
    strip
    tar
    zstd
)

missing_bootstrap=()
for command_name in bash find python3 sort; do
    command -v "$command_name" >/dev/null 2>&1 || \
        missing_bootstrap+=("$command_name")
done
if ((${#missing_bootstrap[@]} > 0)); then
    printf 'Missing required host tools:\n' >&2
    printf '  %s\n' "${missing_bootstrap[@]}" >&2
    printf 'Install them on the host, then rerun ./build.sh.\n' >&2
    exit 1
fi

mapfile -t recipes < <(
    find \
        "$ROOT/000-kernel" \
        "$ROOT/001-runtime" \
        "$ROOT/002-system" \
        "$ROOT/003-graphical" \
        "$ROOT/004-desktop" \
        -mindepth 2 -maxdepth 2 -type f -name build.sh -print |
        LC_ALL=C sort
)

required_commands=("${framework_commands[@]}")
for recipe in "${recipes[@]}"; do
    if ! grep -Fq 'recipe_main "$@"' "$recipe"; then
        continue
    fi
    mapfile -t recipe_commands < <(
        "$recipe" --print-metadata |
            python3 -c '
import json
import sys
for command in json.load(sys.stdin)["makedepends"]:
    print(command)
'
    )
    required_commands+=("${recipe_commands[@]}")
done

mapfile -t required_commands < <(
    printf '%s\n' "${required_commands[@]}" |
        sed '/^$/d' |
        LC_ALL=C sort -u
)

missing_commands=()
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || \
        missing_commands+=("$command_name")
done

if ((${#missing_commands[@]} > 0)); then
    printf 'Missing required host tools:\n' >&2
    printf '  %s\n' "${missing_commands[@]}" >&2
    printf 'Install them on the host, then rerun ./build.sh.\n' >&2
    exit 1
fi
