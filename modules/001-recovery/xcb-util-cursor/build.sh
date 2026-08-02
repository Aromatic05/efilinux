#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=xcb-util-cursor
pkgver=0.1.5
depends=(glibc xcb-util-image xcb-util-renderutil xorg)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/$pkgname-$pkgver.tar.xz"
    download "https://xorg.freedesktop.org/archive/individual/lib/$pkgname-$pkgver.tar.xz" "$archive"
    checksum sha256 0caf99b0d60970f81ce41c7ba694e5eaaf833227bb2cbcdb2f6dc9666a663c57 "$archive"
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
    package_add_library_family keep 'libxcb-cursor.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
