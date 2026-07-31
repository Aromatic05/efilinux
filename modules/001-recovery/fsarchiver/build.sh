#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=fsarchiver
pkgver=0.8.9
depends=(bzip2 e2fsprogs glibc libgcrypt lz4 lzo util-linux xz zlib zstd)
builddepends=()
makedepends=(autoconf automake gcc make pkg-config)
prepare() {
    local archive="$downloaddir/fsarchiver-$pkgver.tar.gz"
    download "https://github.com/fdupoux/fsarchiver/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 072e62c938f5c971ac56c4be64fcf9dd422c17f87d5027373e93d280bb9ff768 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    (cd "$srcdir/source" && autoreconf -fi)
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --sbindir=/usr/bin \
        --enable-lzma \
        --enable-lzo \
        --enable-lz4 \
        --enable-zstd \
        --disable-devel \
        --disable-static \
        --with-debug-level=0 \
        --with-log-dir=/tmp
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin/fsarchiver"; }
package() { package_keep /usr/bin/fsarchiver; }
recipe_main "$@"
