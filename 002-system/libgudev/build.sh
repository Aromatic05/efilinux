#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories

package="libgudev-$LIBGUDEV_VERSION"
recipe_inputs=(
    "$ROOT/001-runtime/config.sh"
    "$ROOT/002-system/desktop-config.sh"
)
if binary_package_restore_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"; then
    exit 0
fi

archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download \
    "https://download.gnome.org/sources/libgudev/$LIBGUDEV_VERSION/$package.tar.xz" \
    "$archive"
verify_sha256 "$LIBGUDEV_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring libgudev against the SysVinit udev runtime"
CC=gcc \
CFLAGS="$(target_cflags)" \
LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$PACKAGE_SOURCE" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        --wrap-mode=nodownload \
        -Dtests=disabled \
        -Dintrospection=disabled \
        -Dvapi=disabled \
        -Dgtk_doc=false

log "Building libgudev"
meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"

binary_package_publish_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
