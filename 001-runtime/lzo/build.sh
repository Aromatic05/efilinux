#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=lzo
pkgver=2.10

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/lzo-$pkgver.tar.gz"

    download \
        "https://www.oberhumer.com/opensource/lzo/download/lzo-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072 \
        "$archive"
    extract "$archive" "$srcdir/lzo"
}

build() {
    log "Configuring LZO"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/lzo/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --enable-shared \
            --disable-static

    log "Building LZO"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    rm -f "$develdir/usr/lib"/*.la
    strip_all "$develdir/usr/lib"
}

package() {
    local library_target

    library_target=$(readlink -- "$pkgdir/usr/lib/liblzo2.so.2")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "LZO SONAME target is missing: $library_target"

    package_keep \
        /usr/lib/liblzo2.so.2 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
