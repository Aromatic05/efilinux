#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make gcc md5sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/xz-$XZ_VERSION.tar.xz"
source_directory="$EFILINUX_BUILD/sources/xz-$XZ_VERSION"
build_directory="$EFILINUX_BUILD/xz-$XZ_VERSION"
staging_directory="$EFILINUX_BUILD/staging/xz"
target_flags="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic -B$EFILINUX_SYSROOT/usr/lib/ --sysroot=$EFILINUX_SYSROOT"

download \
    "https://github.com/tukaani-project/xz/releases/download/v$XZ_VERSION/xz-$XZ_VERSION.tar.xz" \
    "$archive"
verify_md5 "$XZ_MD5" "$archive"
extract_source "$archive" "$source_directory"
reset_directory "$build_directory"
reset_directory "$staging_directory"

log "Configuring XZ Utils"
cd "$build_directory"
CC=gcc CFLAGS="$target_flags" LDFLAGS="$target_flags" \
    "$source_directory/configure" \
        --prefix=/usr \
        --libdir=/usr/lib \
        --disable-static \
        --disable-doc \
        --disable-nls

log "Building XZ Utils"
make -j"$EFILINUX_JOBS"
make DESTDIR="$staging_directory" install

cp -a "$staging_directory/." "$EFILINUX_SYSROOT/"
