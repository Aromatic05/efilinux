#!/usr/bin/env bash

set -euo pipefail

required_commands=(
    autoreconf
    awk
    bc
    bison
    curl
    depmod
    flex
    file
    fakeroot
    find
    getcap
    getfacl
    g++
    gawk
    gcc
    grep
    gzip
    install
    make
    md5sum
    meson
    modinfo
    msgfmt
    msgmerge
    ninja
    openssl
    patch
    perl
    pkg-config
    python3
    readelf
    sed
    sha256sum
    sort
    strip
    tar
    tclsh
    unzip
    xargs
    xgettext
    zstd
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
