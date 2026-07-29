#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories

package="dbus-$DBUS_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"

prepare_package "$package"
download "https://dbus.freedesktop.org/releases/dbus/$package.tar.xz" "$archive"
verify_sha256 "$DBUS_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring D-Bus"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$PACKAGE_SOURCE" \
        --prefix=/usr --libdir=lib --sysconfdir=/etc \
        --localstatedir=/var --buildtype=release \
        -Dauto_features=disabled \
        -Dapparmor=disabled -Dlibaudit=disabled -Dselinux=disabled \
        -Dsystemd=disabled -Dlaunchd=disabled -Dkqueue=disabled \
        -Ddoxygen_docs=disabled -Dducktype_docs=disabled \
        -Dmodular_tests=disabled -Dqt_help=disabled \
        -Depoll=enabled -Dinotify=enabled \
        -Dasserts=false -Dchecks=true -Dintrusive_tests=false \
        -Dinstalled_tests=false -Dmessage_bus=true -Dtools=true \
        -Dtraditional_activation=true -Duser_session=false \
        -Ddbus_user=dbus -Druntime_dir=/run \
        -Dsystem_pid_file=/run/dbus/pid \
        -Dsystem_socket=/run/dbus/system_bus_socket

log "Building D-Bus"
meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"

find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \
    \( -name '*.a' -o -name '*.la' \) -delete
rm -rf "$PACKAGE_STAGING/usr/share/doc"

binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
