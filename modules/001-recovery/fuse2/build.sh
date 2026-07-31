#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=fuse2
pkgver=2.9.9
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/fuse-$pkgver.tar.gz"
    download "https://github.com/libfuse/libfuse/releases/download/fuse-$pkgver/fuse-$pkgver.tar.gz" "$archive"
    checksum sha256 d0e69d5d608cc22ff4843791ad097f554dd32540ddc9bed7638cc6fea7c1b4b5 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --enable-lib \
        --disable-util \
        --disable-example \
        --disable-mtab \
        --disable-rpath \
        --with-pkgconfigdir=/usr/lib/pkgconfig
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f -name '*.a' -delete
    strip_all "$develdir/usr/lib"
}
package() {
    local -a keep=()
    package_add_library_family keep 'libfuse.so.2*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
