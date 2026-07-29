#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

ensure_directories
package="glibc-$GLIBC_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi

require_command bison curl g++ gawk gcc make md5sum perl python3 tar
prepare_package "$package"
archive="$EFILINUX_DOWNLOADS/glibc-$GLIBC_VERSION.tar.xz"

download \
    "https://ftpmirror.gnu.org/glibc/glibc-$GLIBC_VERSION.tar.xz" \
    "$archive"
verify_md5 "$GLIBC_MD5" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring glibc"
cd "$PACKAGE_BUILD"
CFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
CXXFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
"$PACKAGE_SOURCE/configure" \
    --prefix=/usr \
    --with-headers="$EFILINUX_SYSROOT/usr/include" \
    --enable-kernel=6.1 \
    --disable-werror \
    libc_cv_slibdir=/usr/lib

log "Building glibc"
CFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
CXXFLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install

binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
