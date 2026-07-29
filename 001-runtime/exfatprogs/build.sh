#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make pkg-config sha256sum tar
ensure_directories
package="exfatprogs-$EXFATPROGS_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://github.com/exfatprogs/exfatprogs/releases/download/$EXFATPROGS_VERSION/$package.tar.xz" "$archive"
verify_sha256 "$EXFATPROGS_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring exfatprogs"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    "$PACKAGE_SOURCE/configure" --prefix=/usr --bindir=/usr/bin --sbindir=/usr/bin \
        --disable-static
log "Building exfatprogs"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
