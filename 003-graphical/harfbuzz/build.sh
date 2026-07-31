#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=harfbuzz
pkgver=14.2.1

depends=(freetype glibc libpng zlib)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/harfbuzz-$pkgver.tar.xz"

    download \
        "https://github.com/harfbuzz/harfbuzz/releases/download/$pkgver/harfbuzz-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        a54a5d8e9380a41fbb762ce367bcbf7704792dfca0d93f1bbca86c5a57902e0e \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dglib=disabled \
        -Dgobject=disabled \
        -Dcairo=disabled \
        -Dchafa=disabled \
        -Dpng=enabled \
        -Dzlib=enabled \
        -Dicu=disabled \
        -Dgraphite2=disabled \
        -Dfreetype=enabled \
        -Dfontations=disabled \
        -Dharfrust=disabled \
        -Dkbts=disabled \
        -Dwasm=disabled \
        -Draster=enabled \
        -Dvector=enabled \
        -Dgpu=disabled \
        -Dgpu_demo=disabled \
        -Dsubset=enabled \
        -Dtests=disabled \
        -Dintrospection=disabled \
        -Ddocs=disabled \
        -Dutilities=disabled \
        -Dbenchmark=disabled
    target_meson_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libharfbuzz.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
