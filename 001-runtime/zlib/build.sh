#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make gcc md5sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/zlib-$ZLIB_VERSION.tar.gz"
source_directory="$EFILINUX_BUILD/sources/zlib-$ZLIB_VERSION"
staging_directory="$EFILINUX_BUILD/staging/zlib"
target_flags="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic -B$EFILINUX_SYSROOT/usr/lib/ --sysroot=$EFILINUX_SYSROOT"

download "https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz" "$archive"
verify_md5 "$ZLIB_MD5" "$archive"
extract_source "$archive" "$source_directory"
reset_directory "$staging_directory"

log "Configuring zlib"
cd "$source_directory"
CC=gcc CFLAGS="$target_flags" LDFLAGS="$target_flags" \
    ./configure --prefix=/usr --libdir=/usr/lib

log "Building zlib"
make -j"$EFILINUX_JOBS"
make DESTDIR="$staging_directory" install

cp -a "$staging_directory/." "$EFILINUX_SYSROOT/"
