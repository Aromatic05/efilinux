#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libsigcxx
pkgver=2.12.1
depends=(glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libsigc++-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/libsigc%2B%2B/2.12/libsigc%2B%2B-$pkgver.tar.xz" "$archive"
    checksum sha256 a9dbee323351d109b7aee074a9cb89ca3e7bcf8ad8edef1851f4cf359bd50843 "$archive"
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
    package_add_library_family keep 'libsigc-2.0.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
