#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=sqlite
pkgver=3.53.4
sourcever=3530400

depends=(glibc zlib)
builddepends=()
makedepends=(gcc make unzip)

prepare() {
    local archive="$downloaddir/sqlite-src-$sourcever.zip"
    download "https://www.sqlite.org/2026/sqlite-src-$sourcever.zip" "$archive"
    checksum sha256 d18fa15aec74d8c17e1463f861095adc01b5ad190256acb4f91d22f0368d232b "$archive"
    extract_zip "$archive" "$srcdir/sqlite" "sqlite-src-$sourcever"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/sqlite/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-tcl \
            --disable-static \
            --disable-readline \
            --soname=legacy
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libsqlite3.so.0*'
    package_add_library_family keep 'libsqlite3.so.3*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
