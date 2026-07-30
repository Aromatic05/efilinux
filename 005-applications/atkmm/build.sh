#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=atkmm
pkgver=2.28.5
depends=(at-spi2-core glibc glibmm libsigcxx)
builddepends=()
makedepends=(gcc g++ meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/atkmm-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/atkmm/2.28/atkmm-$pkgver.tar.xz" "$archive"
    checksum sha256 ae449192a582a2582a95e0602b15d792bbd639e836339b81ef916aa87540ac5c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" -Dbuild-documentation=false
    target_meson_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libatkmm-1.6.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
