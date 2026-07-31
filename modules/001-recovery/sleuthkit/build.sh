#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=sleuthkit
pkgver=4.15.0
depends=(gcc-libs glibc sqlite zlib)
builddepends=()
makedepends=(autoconf automake gcc g++ libtool make pkg-config)
prepare() {
    local archive="$downloaddir/sleuthkit-$pkgver.tar.gz"
    download "https://github.com/sleuthkit/sleuthkit/archive/refs/tags/sleuthkit-$pkgver.tar.gz" "$archive"
    checksum sha256 4888ef54f9b404853712945218b3168696569db9167d7e01ec76e44b6c05c71c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_autotools_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --disable-java \
        --disable-cppunit \
        --enable-offline \
        --enable-multithreading \
        --without-afflib \
        --without-libbfio \
        --without-libewf \
        --without-libvhdi \
        --without-libvmdk \
        --without-libvslvm \
        --with-zlib
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(/usr/bin/)
    package_add_library_family keep 'libtsk.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
