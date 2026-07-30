#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=dbus
pkgver=1.16.2

depends=(expat glibc)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/dbus-$pkgver.tar.xz"
    download "https://dbus.freedesktop.org/releases/dbus/dbus-$pkgver.tar.xz" "$archive"
    checksum sha256 0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2 "$archive"
    extract "$archive" "$srcdir/dbus"
}

build() {
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/dbus" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            -Dauto_features=disabled \
            -Dapparmor=disabled \
            -Dlibaudit=disabled \
            -Dselinux=disabled \
            -Dsystemd=disabled \
            -Dlaunchd=disabled \
            -Dkqueue=disabled \
            -Ddoxygen_docs=disabled \
            -Dducktype_docs=disabled \
            -Dmodular_tests=disabled \
            -Dqt_help=disabled \
            -Depoll=enabled \
            -Dinotify=enabled \
            -Dasserts=false \
            -Dchecks=true \
            -Dintrusive_tests=false \
            -Dinstalled_tests=false \
            -Dmessage_bus=true \
            -Dtools=true \
            -Dtraditional_activation=true \
            -Duser_session=false \
            -Ddbus_user=dbus \
            -Druntime_dir=/run \
            -Dsystem_pid_file=/run/dbus/pid \
            -Dsystem_socket=/run/dbus/system_bus_socket
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    rm -rf "$develdir/usr/share/doc"
    chmod 4755 "$develdir/usr/libexec/dbus-daemon-launch-helper"
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib" \
        "$develdir/usr/libexec"
}

package() {
    local -a keep=(
        /usr/bin/dbus-daemon
        /usr/bin/dbus-monitor
        /usr/bin/dbus-run-session
        /usr/bin/dbus-send
        /usr/bin/dbus-update-activation-environment
        /usr/bin/dbus-uuidgen
        /usr/libexec/dbus-daemon-launch-helper
        /etc/dbus-1/
        /usr/share/dbus-1/
    )
    package_add_library_family keep 'libdbus-1.so.3*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
