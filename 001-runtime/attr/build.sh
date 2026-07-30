#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=attr
pkgver=2.6.0

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
    pkg-config
)

prepare() {
    local archive="$downloaddir/attr-$pkgver.tar.gz"

    download \
        "https://download.savannah.gnu.org/releases/attr/attr-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        d42fa374513180bb48cb11a46696f488240e5124ff1e6ad88b0abff706985612 \
        "$archive"
    extract "$archive" "$srcdir/attr"
}

build() {
    log "Configuring Attr"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig" \
        "$srcdir/attr/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --disable-nls

    log "Building Attr"
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

    library_target=$(readlink -- "$pkgdir/usr/lib/libattr.so.1")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "Attr SONAME target is missing: $library_target"

    package_keep \
        /usr/bin/getfattr \
        /usr/bin/setfattr \
        /usr/lib/libattr.so.1 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
