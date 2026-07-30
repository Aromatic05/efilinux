#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=pcre2
pkgver=10.47

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/pcre2-$pkgver.tar.bz2"

    download \
        "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$pkgver/pcre2-$pkgver.tar.bz2" \
        "$archive"
    checksum \
        sha256 \
        47fe8c99461250d42f89e6e8fdaeba9da057855d06eb7fc08d9ca03fd08d7bc7 \
        "$archive"
    extract "$archive" "$srcdir/pcre2"
}

build() {
    log "Configuring PCRE2"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/pcre2/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --disable-pcre2-16 \
            --disable-pcre2-32 \
            --enable-jit

    log "Building PCRE2"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    rm -f "$develdir/usr/lib"/*.la
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local library_target

    library_target=$(readlink -- "$pkgdir/usr/lib/libpcre2-8.so.0")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "PCRE2 SONAME target is missing: $library_target"

    package_keep \
        /usr/lib/libpcre2-8.so.0 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
