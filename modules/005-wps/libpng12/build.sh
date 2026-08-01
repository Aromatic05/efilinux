#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libpng12
pkgver=1.2.59
depends=(glibc zlib)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libpng-$pkgver.tar.xz"
    download "https://downloads.sourceforge.net/project/libpng/libpng12/$pkgver/libpng-$pkgver.tar.xz" "$archive"
    checksum sha256 b4635f15b8adccc8ad0934eea485ef59cc4cae24d0f0300a9a941e51974ffcc7 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared
    target_make_install "$builddir" "$develdir"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    rm -rf "$develdir/usr/share/man"
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libpng12.so.*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
