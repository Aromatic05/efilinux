#!/usr/bin/env bash

set -euo pipefail

required_commands=(
    bc
    bison
    curl
    flex
    find
    g++
    gawk
    gcc
    grep
    gzip
    make
    md5sum
    openssl
    perl
    python3
    readelf
    sed
    sha256sum
    sort
    tar
)

missing_commands=()
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || \
        missing_commands+=("$command_name")
done

if (( ${#missing_commands[@]} > 0 )); then
    printf 'Missing required host tools:\n' >&2
    printf '  %s\n' "${missing_commands[@]}" >&2
    printf 'Install them on the host, then rerun ./build.sh.\n' >&2
    exit 1
fi
