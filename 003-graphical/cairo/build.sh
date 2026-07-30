#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=cairo
pkgver=1.18.4

depends=(fontconfig freetype glib glibc libpng pixman xorg zlib)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/cairo-$pkgver.tar.xz"
    download "https://cairographics.org/releases/cairo-1.18.4.tar.xz" "$archive"
    checksum sha256 445ed8208a6e4823de1226a74ca319d3600e83f6369f99b14265006599c32ccb "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Ddwrite=disabled \
        -Dfontconfig=enabled \
        -Dfreetype=enabled \
        -Dpng=enabled \
        -Dquartz=disabled \
        -Dtee=disabled \
        -Dxcb=enabled \
        -Dxlib=enabled \
        -Dxlib-xcb=enabled \
        -Dzlib=enabled \
        -Dtests=disabled \
        -Dlzo=disabled \
        -Dgtk2-utils=disabled \
        -Dglib=enabled \
        -Dspectre=disabled \
        -Dsymbol-lookup=disabled \
        -Dgtk_doc=false
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=()
    package_add_library_family keep 'libcairo*.so.*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
