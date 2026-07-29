#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make pkg-config sha256sum tar
ensure_directories
package="e2fsprogs-$E2FSPROGS_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
prepare_package "$package"
download "https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v$E2FSPROGS_VERSION/$package.tar.gz" "$archive"
verify_sha256 "$E2FSPROGS_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring E2fsprogs"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    "$PACKAGE_SOURCE/configure" \
        --prefix=/usr \
        --bindir=/usr/bin \
        --sbindir=/usr/bin \
        --libdir=/usr/lib \
        --sysconfdir=/etc \
        --with-root-prefix=/usr \
        --enable-elf-shlibs \
        --disable-uuidd \
        --disable-fuse2fs \
        --disable-nls \
        --disable-rpath \
        --without-libarchive \
        --with-udev-rules-dir=/usr/lib/udev/rules.d \
        --with-systemd-unit-dir=no
log "Building E2fsprogs"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
