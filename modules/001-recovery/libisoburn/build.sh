#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libisoburn
pkgver=1.5.6
depends=(acl glibc libburn libisofs readline zlib)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/libisoburn-$pkgver.tar.gz"
    download "https://files.libburnia-project.org/releases/libisoburn-$pkgver.tar.gz" "$archive"
    checksum sha256 2b80a6f73dd633a5d243facbe97a15e5c9a07644a5e1a242c219b9375a45f71b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --enable-shared
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(/usr/bin/xorriso /usr/bin/xorrisofs /usr/bin/osirrox)
    package_add_library_family keep 'libisoburn.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
