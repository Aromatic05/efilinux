#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libffi
pkgver=3.7.1

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/libffi-$pkgver.tar.gz"

    download \
        "https://github.com/libffi/libffi/releases/download/v$pkgver/libffi-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        d5e9a6638ddbd2513ddb54518eb67e4bbe6fa707bcc01c10f6212f0a088d819d \
        "$archive"
    extract "$archive" "$srcdir/libffi"
}

build() {
    log "Configuring libffi"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/libffi/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --disable-docs

    log "Building libffi"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    rm -f "$develdir/usr/lib"/*.la
    strip_all "$develdir/usr/lib"
}

package() {
    local library_target

    library_target=$(readlink -- "$pkgdir/usr/lib/libffi.so.8")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "libffi SONAME target is missing: $library_target"

    package_keep \
        /usr/lib/libffi.so.8 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
