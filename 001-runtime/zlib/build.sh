#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=zlib
pkgver=1.3.2

depends=(
    glibc
)

builddepends=()

makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/zlib-$pkgver.tar.gz"

    download \
        "https://zlib.net/fossils/zlib-$pkgver.tar.gz" \
        "$archive"
    checksum \
        md5 \
        a1e6c958597af3c67d162995a342138a \
        "$archive"
    extract "$archive" "$srcdir/zlib"
}

build() {
    log "Configuring zlib"
    cd "$srcdir/zlib"
    CC=gcc CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        ./configure --prefix=/usr --libdir=/usr/lib

    log "Building zlib"
    make
    make DESTDIR="$develdir" install
}

check() {
    make -C "$srcdir/zlib" check
}

devel() {
    rm -rf "$develdir/usr/share/man"
    find "$develdir/usr/share" -depth -type d -empty -delete 2>/dev/null || true
    strip_all "$develdir/usr/lib"
}

package() {
    rm -rf \
        "$pkgdir/usr/include" \
        "$pkgdir/usr/lib/pkgconfig"
    find "$pkgdir/usr/lib" -type f -name '*.a' -delete
}

recipe_main "$@"
