#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make gcc md5sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/zstd-$ZSTD_VERSION.tar.gz"
source_directory="$EFILINUX_BUILD/sources/zstd-$ZSTD_VERSION"
staging_directory="$EFILINUX_BUILD/staging/zstd"
target_flags="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic -B$EFILINUX_SYSROOT/usr/lib/ --sysroot=$EFILINUX_SYSROOT"

download \
    "https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/zstd-$ZSTD_VERSION.tar.gz" \
    "$archive"
verify_md5 "$ZSTD_MD5" "$archive"
extract_source "$archive" "$source_directory"
reset_directory "$staging_directory"

log "Building Zstandard"
CC=gcc CFLAGS="$target_flags" LDFLAGS="$target_flags" \
make -C "$source_directory" -j"$EFILINUX_JOBS" \
    ZSTD_LEGACY_SUPPORT=0 \
    ZSTD_BUILD_STATIC=0

CC=gcc CFLAGS="$target_flags" LDFLAGS="$target_flags" \
make -C "$source_directory" \
    prefix=/usr \
    libdir=/usr/lib \
    DESTDIR="$staging_directory" \
    ZSTD_LEGACY_SUPPORT=0 \
    ZSTD_BUILD_STATIC=0 \
    install

rm -f "$staging_directory/usr/lib/libzstd.a"
cp -a "$staging_directory/." "$EFILINUX_SYSROOT/"
