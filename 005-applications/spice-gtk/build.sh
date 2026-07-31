#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=spice-gtk
pkgver=0.42
depends=(cairo gdk-pixbuf glib glibc gst-plugins-base gstreamer gtk3 json-glib openssl pixman)
builddepends=(spice-protocol)
makedepends=(gcc meson ninja pkg-config python3)
prepare() {
    local archive="$downloaddir/spice-gtk-$pkgver.tar.xz"
    download "https://www.spice-space.org/download/gtk/spice-gtk-$pkgver.tar.xz" "$archive"
    checksum sha256 9380117f1811ad1faa1812cb6602479b6290d4a0d8cc442d44427f7f6c0e7a58 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --auto-features=disabled \
        -Dgtk=enabled \
        -Dusbredir=disabled \
        -Dsmartcard=disabled \
        -Dpolkit=disabled \
        -Dwebdav=disabled \
        -Dlz4=disabled \
        -Dopus=disabled \
        -Dgtk_doc=disabled \
        -Dintrospection=disabled \
        -Dvapi=disabled \
        -Dwayland-protocols=disabled \
        -Degl=disabled \
        -Dsasl=disabled
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libspice-client-glib-2.0.so.*'
    package_add_library_family keep 'libspice-client-gtk-3.0.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
