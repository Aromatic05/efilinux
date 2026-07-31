#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=bzip2
pkgver=1.0.8
depends=(glibc)
builddepends=()
makedepends=(gcc)
prepare() {
    local archive="$downloaddir/bzip2-$pkgver.tar.gz"
    download "https://sourceware.org/pub/bzip2/bzip2-$pkgver.tar.gz" "$archive"
    checksum sha256 ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local objects=(blocksort huffman crctable randtable compress decompress bzlib)
    local object
    mkdir -p "$builddir"
    for object in "${objects[@]}"; do
        "$CC" $CPPFLAGS $CFLAGS -fPIC -c "$srcdir/source/$object.c" -o "$builddir/$object.o"
    done
    "$CC" $LDFLAGS -shared -Wl,-soname,libbz2.so.1.0 \
        -o "$builddir/libbz2.so.1.0.8" "$builddir"/*.o
    install -Dm0644 "$srcdir/source/bzlib.h" "$develdir/usr/include/bzlib.h"
    install -Dm0755 "$builddir/libbz2.so.1.0.8" "$develdir/usr/lib/libbz2.so.1.0.8"
    ln -s libbz2.so.1.0.8 "$develdir/usr/lib/libbz2.so.1.0"
    ln -s libbz2.so.1.0 "$develdir/usr/lib/libbz2.so"
}
devel() { strip_all "$develdir/usr/lib/libbz2.so.1.0.8"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libbz2.so.1.0*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
