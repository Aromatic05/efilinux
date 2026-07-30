#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=acl
pkgver=2.4.0

depends=(
    glibc
    attr
)
builddepends=()
makedepends=(
    gcc
    make
    pkg-config
)

prepare() {
    local archive="$downloaddir/acl-$pkgver.tar.xz"

    download \
        "https://download.savannah.gnu.org/releases/acl/acl-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        e661131456d2708a01c614a0f400e11d7d1bfaeb6f3e74b75bb980b72f0161a3 \
        "$archive"
    extract "$archive" "$srcdir/acl"
}

build() {
    log "Configuring ACL"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig" \
        "$srcdir/acl/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --disable-nls

    log "Building ACL"
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

    library_target=$(readlink -- "$pkgdir/usr/lib/libacl.so.1")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "ACL SONAME target is missing: $library_target"

    package_keep \
        /usr/bin/chacl \
        /usr/bin/getfacl \
        /usr/bin/setfacl \
        /usr/lib/libacl.so.1 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
