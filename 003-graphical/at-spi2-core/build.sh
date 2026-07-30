#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=at-spi2-core
pkgver=2.60.5

depends=(dbus glib glibc libxml2 xorg)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/at-spi2-core-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/at-spi2-core/2.60/at-spi2-core-2.60.5.tar.xz" "$archive"
    checksum sha256 6059a77d507438ff6c8d6d06025f8f9f5774fa0f8eabe9c9b059b1cc41e1bbc0 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Ddefault_bus=dbus-daemon \
        -Ddbus_daemon=/usr/bin/dbus-daemon \
        -Duse_systemd=false \
        -Dgtk2_atk_adaptor=false \
        -Ddocs=false \
        -Dintrospection=disabled \
        -Dx11=enabled \
        -Ddbus_glib=disabled
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
    rm -rf "$develdir/etc/xdg/Xwayland-session.d"
}

package() {
    local -a keep=(
        /etc/xdg/autostart/at-spi-dbus-bus.desktop
        /usr/libexec/
        /usr/share/dbus-1/
        /usr/share/defaults/at-spi2/
    )
    package_add_library_family keep 'libatk-1.0.so.0*'
    package_add_library_family keep 'libatk-bridge-2.0.so.0*'
    package_add_library_family keep 'libatspi.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
