#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

ensure_directories
package="zstd-$ZSTD_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi

require_command curl gcc make md5sum tar
prepare_package "$package"
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"

download \
    "https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/$package.tar.gz" \
    "$archive"
verify_md5 "$ZSTD_MD5" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Building Zstandard"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
make -C "$PACKAGE_SOURCE" -j"$EFILINUX_JOBS" \
    ZSTD_LEGACY_SUPPORT=0 \
    ZSTD_BUILD_STATIC=0

CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
make -C "$PACKAGE_SOURCE" \
    prefix=/usr \
    libdir=/usr/lib \
    DESTDIR="$PACKAGE_STAGING" \
    ZSTD_LEGACY_SUPPORT=0 \
    ZSTD_BUILD_STATIC=0 \
    install

rm -f "$PACKAGE_STAGING/usr/lib/libzstd.a"
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
