#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make pkg-config sha256sum tar
ensure_directories
package="xfsprogs-$XFS_PROGS_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://www.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/$package.tar.xz" "$archive"
verify_sha256 "$XFS_PROGS_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring XFSprogs"
cd "$PACKAGE_SOURCE"
ac_cv_search_dm_task_create=no \
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    "$PACKAGE_SOURCE/configure" --prefix=/usr --bindir=/usr/bin --sbindir=/usr/bin \
        --libdir=/usr/lib --enable-shared=yes --enable-static=no \
        --enable-editline=no --enable-lto=no --enable-scrub=no --enable-libicu=no
log "Building XFSprogs"
make -j"$EFILINUX_JOBS"
make DIST_ROOT="$PACKAGE_STAGING" install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true
merge_sysroot "$PACKAGE_STAGING"
