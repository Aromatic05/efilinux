#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libnotify
pkgver=0.8.7

depends=(gdk-pixbuf glib glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libnotify-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/libnotify/0.8/libnotify-0.8.7.tar.xz" "$archive"
    checksum sha256 4be15202ec4184fce1ac15997ece5530d2be32fe9573875aeb10e3b573858748 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Dtests=false \
        -Dintrospection=disabled \
        -Dman=false \
        -Dgtk_doc=false \
        -Ddocbook_docs=disabled
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=()
    package_add_library_family keep 'libnotify.so.4*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
