#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libxklavier
pkgver=5.4

depends=(glib glibc iso-codes xorg)
builddepends=()
makedepends=(autoreconf gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libxklavier-$pkgver.tar.gz"
    download "https://gitlab.freedesktop.org/archived-projects/libxklavier/-/archive/libxklavier-$pkgver/libxklavier-libxklavier-$pkgver.tar.gz" "$archive"
    checksum sha256 e1638599e9229e6f6267b70b02e41940b98ba29b3a37e221f6e59ff90100c3da "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    sed -i 's#iso_codes_prefix=`$PKG_CONFIG --variable=prefix iso-codes`#iso_codes_prefix=/usr#' "$srcdir/source/configure.ac"
    target_autotools_configure "$srcdir/source" "$builddir" \
        --disable-static --disable-silent-rules --disable-gtk-doc --disable-introspection \
        --with-xkb-base=/usr/share/X11/xkb --with-xkb-bin-base=/usr/bin
    target_make_install "$builddir" "$develdir"
}

devel() {
    prune_translations "$develdir"
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libxklavier.so.16*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
