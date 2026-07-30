#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=json-glib
pkgver=1.10.8
depends=(glib glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/json-glib-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/json-glib/1.10/json-glib-$pkgver.tar.xz" "$archive"
    checksum sha256 55c5c141a564245b8f8fbe7698663c87a45a7333c2a2c56f06f811ab73b212dd "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" -Ddocumentation=disabled -Dintrospection=disabled -Dtests=false -Dconformance=false -Dinstalled_tests=false
    target_meson_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libjson-glib-1.0.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
