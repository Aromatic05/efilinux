#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make gcc g++ bison gawk perl python3 md5sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/glibc-$GLIBC_VERSION.tar.xz"
source_directory="$EFILINUX_BUILD/sources/glibc-$GLIBC_VERSION"
build_directory="$EFILINUX_BUILD/glibc-$GLIBC_VERSION"

download \
    "https://ftpmirror.gnu.org/glibc/glibc-$GLIBC_VERSION.tar.xz" \
    "$archive"
verify_md5 "$GLIBC_MD5" "$archive"
extract_source "$archive" "$source_directory"
reset_directory "$build_directory"

log "Configuring glibc"
cd "$build_directory"
CFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
CXXFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
"$source_directory/configure" \
    --prefix=/usr \
    --with-headers="$EFILINUX_SYSROOT/usr/include" \
    --enable-kernel=6.1 \
    --disable-werror \
    libc_cv_slibdir=/usr/lib

log "Building glibc"
CFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
CXXFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
make -j"$EFILINUX_JOBS"
make DESTDIR="$EFILINUX_SYSROOT" install
