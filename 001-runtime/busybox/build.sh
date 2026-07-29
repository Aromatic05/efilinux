#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

ensure_directories
package="busybox-$BUSYBOX_VERSION"
if binary_package_reuse \
    "$package" "${BASH_SOURCE[0]}" \
    "$ROOT/001-runtime/busybox/minimal.config"; then
    exit 0
fi

require_command awk curl gcc make readelf sha256sum tar
prepare_package "$package"
archive="$EFILINUX_DOWNLOADS/busybox-$BUSYBOX_VERSION.tar.bz2"

download \
    "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2" \
    "$archive"
verify_sha256 "$BUSYBOX_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring BusyBox"
make -C "$PACKAGE_SOURCE" O="$PACKAGE_BUILD" allnoconfig

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
        "$PACKAGE_BUILD/.config" \
        > "$PACKAGE_BUILD/.config.tmp"
    mv "$PACKAGE_BUILD/.config.tmp" "$PACKAGE_BUILD/.config"
done < "$ROOT/001-runtime/busybox/minimal.config"

sed -i \
    "s@^CONFIG_SYSROOT=.*@CONFIG_SYSROOT=\"$EFILINUX_SYSROOT\"@" \
    "$PACKAGE_BUILD/.config"
sed -i \
    "s@^CONFIG_EXTRA_CFLAGS=.*@CONFIG_EXTRA_CFLAGS=\"-B$EFILINUX_SYSROOT/usr/lib/ -march=$EFILINUX_X86_64_LEVEL -mtune=generic\"@" \
    "$PACKAGE_BUILD/.config"

# BusyBox documents a possible coarse-mtime race after editing .config.
sleep 1
make -C "$PACKAGE_SOURCE" O="$PACKAGE_BUILD" oldconfig < <(yes '')

grep -qx 'CONFIG_FEATURE_MODUTILS_ALIAS=y' "$PACKAGE_BUILD/.config" || \
    die "BusyBox module alias support is disabled"
grep -qx 'CONFIG_TEST1=y' "$PACKAGE_BUILD/.config" || \
    die "BusyBox [ applet is disabled"
grep -qx 'CONFIG_DEFAULT_MODULES_DIR="/lib/modules"' "$PACKAGE_BUILD/.config" || \
    die "BusyBox default module directory is incorrect"
grep -qx 'CONFIG_DEFAULT_DEPMOD_FILE="modules.dep"' "$PACKAGE_BUILD/.config" || \
    die "BusyBox depmod filename is incorrect"

log "Building dynamically linked BusyBox against project glibc"
make -C "$PACKAGE_SOURCE" \
    O="$PACKAGE_BUILD" \
    -j"$EFILINUX_JOBS" \
    CC=gcc \
    HOSTCC=gcc

make -C "$PACKAGE_SOURCE" \
    O="$PACKAGE_BUILD" \
    CONFIG_PREFIX="$PACKAGE_STAGING" \
    install

LC_ALL=C readelf --program-headers "$PACKAGE_STAGING/bin/busybox" |
    grep -q 'Requesting program interpreter' || \
    die "BusyBox is not dynamically linked"

binary_package_publish_staging \
    "$package" "${BASH_SOURCE[0]}" \
    "$ROOT/001-runtime/busybox/minimal.config"
