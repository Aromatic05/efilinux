#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=xcb-util-wm
pkgver=0.4.2
depends=(glibc xorg)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/$pkgname-$pkgver.tar.xz"
    download "https://xorg.freedesktop.org/archive/individual/lib/$pkgname-$pkgver.tar.xz" "$archive"
    checksum sha256 62c34e21d06264687faea7edbf63632c9f04d55e72114aa4a57bb95e4f888a0b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --enable-shared
    target_make_install "$builddir" "$develdir"
}
devel() { find "$develdir" -name '*.la' -delete; strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libxcb-ewmh.so.*'
    package_add_library_family keep 'libxcb-icccm.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
