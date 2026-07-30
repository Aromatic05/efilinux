#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=glibmm
pkgver=2.66.9
depends=(glib glibc libsigcxx)
builddepends=()
makedepends=(gcc g++ meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/glibmm-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/glibmm/2.66/glibmm-$pkgver.tar.xz" "$archive"
    checksum sha256 5a026e5602085307c7dcb72b71b07261c40f80914277bef5f8d7f2ecab739bec "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" -Dbuild-examples=false -Dbuild-documentation=false
    target_meson_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libglibmm-2.4.so.1*'
    package_add_library_family keep 'libgiomm-2.4.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
