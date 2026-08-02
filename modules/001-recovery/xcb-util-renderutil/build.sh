#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=xcb-util-renderutil
pkgver=0.3.10
depends=(glibc xorg)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/$pkgname-$pkgver.tar.xz"
    download "https://xorg.freedesktop.org/archive/individual/lib/$pkgname-$pkgver.tar.xz" "$archive"
    checksum sha256 3e15d4f0e22d8ddbfbb9f5d77db43eacd7a304029bf25a6166cc63caa96d04ba "$archive"
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
    package_add_library_family keep 'libxcb-render-util.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
