#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl sha256sum tar
ensure_directories

package="wireless-regdb-$WIRELESS_REGDB_VERSION"
producer=${BASH_SOURCE[0]}
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"

[[ -d "$EFILINUX_ROOTFS" ]] || die "target rootfs has not been built"
set_package_paths "$package"

if binary_package_extract "$package" "$PACKAGE_STAGING" "$producer"; then
    log "Using binary package $(basename -- "$PACKAGE_ARCHIVE")"
else
    download \
        "https://www.kernel.org/pub/software/network/wireless-regdb/$package.tar.xz" \
        "$archive"
    verify_sha256 "$WIRELESS_REGDB_SHA256" "$archive"
    prepare_package "$package"
    extract_source "$archive" "$PACKAGE_SOURCE"

    mkdir -p "$PACKAGE_STAGING/usr/lib/firmware"
    install -m 0644 \
        "$PACKAGE_SOURCE/regulatory.db" \
        "$PACKAGE_STAGING/usr/lib/firmware/regulatory.db"
    install -m 0644 \
        "$PACKAGE_SOURCE/regulatory.db.p7s" \
        "$PACKAGE_STAGING/usr/lib/firmware/regulatory.db.p7s"

    binary_package_create "$package" "$PACKAGE_STAGING" "$producer"
fi

install_rootfs_tree \
    "$package" "$PACKAGE_STAGING/usr/lib/firmware" /usr/lib/firmware
rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
