#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libwnck
pkgver=43.2

depends=(glib glibc gtk3 startup-notification xorg)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libwnck-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/libwnck/43/libwnck-43.2.tar.xz" "$archive"
    checksum sha256 55a7444ec1fbb95c086d40967388f231b5c0bbc8cffaa086bf9290ae449e51d5 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Dstartup_notification=enabled \
        -Dintrospection=disabled \
        -Dgtk_doc=false \
        -Dinstall_tools=false
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=()
    package_add_library_family keep 'libwnck-3.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
