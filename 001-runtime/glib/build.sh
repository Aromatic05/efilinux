#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc meson ninja pkg-config python3 sha256sum tar
ensure_directories

package="glib-$GLIB_VERSION"
recipe_inputs=("$ROOT/001-runtime/config.sh")
if binary_package_restore_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"; then
    exit 0
fi

archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download \
    "https://download.gnome.org/sources/glib/${GLIB_VERSION%.*}/$package.tar.xz" \
    "$archive"
verify_sha256 "$GLIB_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring generic GLib runtime"
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
        -Dselinux=disabled \
        -Dlibmount=disabled \
        -Dman-pages=disabled \
        -Ddtrace=disabled \
        -Dsystemtap=disabled \
        -Dsysprof=disabled \
        -Ddocumentation=false \
        -Dtests=false \
        -Dinstalled_tests=false \
        -Dnls=enabled \
        -Dglib_debug=disabled \
        -Dintrospection=disabled \
        -Dlibelf=disabled \
        -Dfile_monitor_backend=inotify

log "Building generic GLib runtime"
LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" \
LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    meson install -C "$PACKAGE_BUILD"

binary_package_publish_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
