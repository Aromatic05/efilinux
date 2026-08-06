#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libmd
pkgver=1.1.0
depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/libmd-$pkgver.tar.xz"
    download "https://libbsd.freedesktop.org/releases/libmd-$pkgver.tar.xz" "$archive"
    checksum sha256 1bd6aa42275313af3141c7cf2e5b964e8b1fd488025caf2f971f43b00776b332 "$archive"
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
    strip_all "$develdir/usr/lib"
}
package() {
    local -a keep=()
    package_add_library_family keep 'libmd.so.0*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
