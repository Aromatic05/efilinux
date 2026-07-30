#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libxcrypt
pkgver=4.5.2

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/libxcrypt-$pkgver.tar.xz"

    download \
        "https://github.com/besser82/libxcrypt/releases/download/v$pkgver/libxcrypt-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        71513a31c01a428bccd5367a32fd95f115d6dac50fb5b60c779d5c7942aec071 \
        "$archive"
    extract "$archive" "$srcdir/libxcrypt"
}

build() {
    log "Configuring Libxcrypt"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/libxcrypt/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --disable-werror \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no

    log "Building Libxcrypt"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    rm -f "$develdir/usr/lib"/*.la
    strip_all "$develdir/usr/lib"
}

package() {
    local library_target

    library_target=$(readlink -- "$pkgdir/usr/lib/libcrypt.so.2")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "Libxcrypt SONAME target is missing: $library_target"

    package_keep \
        /usr/lib/libcrypt.so.2 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
