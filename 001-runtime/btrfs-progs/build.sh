#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make pkg-config sha256sum tar
ensure_directories
package="btrfs-progs-v$BTRFS_PROGS_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://www.kernel.org/pub/linux/kernel/people/kdave/btrfs-progs/$package.tar.xz" "$archive"
verify_sha256 "$BTRFS_PROGS_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring Btrfs-progs"
cd "$PACKAGE_SOURCE"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    "$PACKAGE_SOURCE/configure" --prefix=/usr --bindir=/usr/bin --sbindir=/usr/bin \
        --libdir=/usr/lib --disable-static --disable-documentation --disable-convert \
        --disable-zoned --disable-libudev --disable-python --with-crypto=builtin
log "Building Btrfs-progs"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
