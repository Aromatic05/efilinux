#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories
package="inih-$INIH_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
prepare_package "$package"
download "https://github.com/benhoyt/inih/archive/refs/tags/$INIH_VERSION.tar.gz" "$archive"
verify_sha256 "$INIH_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring inih"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$PACKAGE_SOURCE" \
        --prefix=/usr --libdir=lib --buildtype=release \
        -Ddefault_library=shared -Dwith_INIReader=false -Dtests=false
log "Building inih"
meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
