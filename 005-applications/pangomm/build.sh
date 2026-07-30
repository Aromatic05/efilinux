#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=pangomm
pkgver=2.46.5
depends=(cairomm glibc glibmm libsigcxx pango)
builddepends=()
makedepends=(gcc g++ meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/pangomm-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/pangomm/2.46/pangomm-$pkgver.tar.xz" "$archive"
    checksum sha256 38ca0b050b065de4e3da0c182df657437757063bbf0c4b6c9567ddba019b1d68 "$archive"
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
    package_add_library_family keep 'libpangomm-2.46.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
