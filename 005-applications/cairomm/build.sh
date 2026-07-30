#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=cairomm
pkgver=1.14.5
depends=(cairo glibc glibmm libsigcxx)
builddepends=()
makedepends=(gcc g++ meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/cairomm-$pkgver.tar.xz"
    download "https://www.cairographics.org/releases/cairomm-$pkgver.tar.xz" "$archive"
    checksum sha256 70136203540c884e89ce1c9edfb6369b9953937f6cd596d97c78c9758a5d48db "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" -Dbuild-examples=false -Dbuild-tests=false -Dbuild-documentation=false
    target_meson_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libcairomm-1.0.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
