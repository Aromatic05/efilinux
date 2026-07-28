#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command awk curl tar make gcc readelf sha256sum
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
    awk \
        -v name="$config_name" \
        -v entry="$config_entry" \
        '
            BEGIN {
                disabled = "# " name " is not set"
                prefix = name "="
                replaced = 0
            }
            $0 == disabled || index($0, prefix) == 1 {
                if (!replaced) {
                    print entry
                    replaced = 1
                }
                next
            }
            { print }
            END {
                if (!replaced)
                    print entry
            }
        ' \
        "$build_directory/.config" \
        > "$build_directory/.config.tmp"
    mv "$build_directory/.config.tmp" "$build_directory/.config"
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

grep -qx 'CONFIG_FEATURE_MODUTILS_ALIAS=y' "$build_directory/.config" || \
    die "BusyBox module alias support is disabled"
grep -qx 'CONFIG_DEFAULT_MODULES_DIR="/lib/modules"' "$build_directory/.config" || \
    die "BusyBox default module directory is incorrect"
grep -qx 'CONFIG_DEFAULT_DEPMOD_FILE="modules.dep"' "$build_directory/.config" || \
    die "BusyBox depmod filename is incorrect"

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
