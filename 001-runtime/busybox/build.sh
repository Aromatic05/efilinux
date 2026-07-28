#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make gcc readelf sha256sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/busybox-$BUSYBOX_VERSION.tar.bz2"
source_directory="$EFILINUX_BUILD/sources/busybox-$BUSYBOX_VERSION"
build_directory="$EFILINUX_BUILD/busybox-$BUSYBOX_VERSION"
staging_directory="$EFILINUX_BUILD/staging/busybox"

download \
    "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2" \
    "$archive"
verify_sha256 "$BUSYBOX_SHA256" "$archive"
extract_source "$archive" "$source_directory"
reset_directory "$build_directory"
reset_directory "$staging_directory"

log "Configuring BusyBox"
make -C "$source_directory" O="$build_directory" allnoconfig

while IFS= read -r config_entry; do
    [[ -z "$config_entry" ]] && continue

    config_name=${config_entry%%=*}
    if grep -q "^# $config_name is not set$" "$build_directory/.config"; then
        sed -i "s/^# $config_name is not set$/$config_entry/" \
            "$build_directory/.config"
    elif grep -q "^$config_name=" "$build_directory/.config"; then
        sed -i "s/^$config_name=.*/$config_entry/" \
            "$build_directory/.config"
    else
        printf '%s\n' "$config_entry" >> "$build_directory/.config"
    fi
done < "$ROOT/001-runtime/busybox/minimal.config"

sed -i \
    "s@^CONFIG_SYSROOT=.*@CONFIG_SYSROOT=\"$EFILINUX_SYSROOT\"@" \
    "$build_directory/.config"
sed -i \
    "s@^CONFIG_EXTRA_CFLAGS=.*@CONFIG_EXTRA_CFLAGS=\"-B$EFILINUX_SYSROOT/usr/lib/ -march=$EFILINUX_X86_64_LEVEL -mtune=generic\"@" \
    "$build_directory/.config"

# BusyBox documents a possible coarse-mtime race after editing .config.
sleep 1
make -C "$source_directory" O="$build_directory" oldconfig < <(yes '')

log "Building dynamically linked BusyBox against project glibc"
make -C "$source_directory" \
    O="$build_directory" \
    -j"$EFILINUX_JOBS" \
    CC=gcc \
    HOSTCC=gcc

make -C "$source_directory" \
    O="$build_directory" \
    CONFIG_PREFIX="$staging_directory" \
    install

LC_ALL=C readelf --program-headers "$staging_directory/bin/busybox" |
    grep -q 'Requesting program interpreter' || \
    die "BusyBox is not dynamically linked"
