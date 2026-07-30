#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=inih
pkgver=r62

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    meson
    ninja
    pkg-config
)

prepare() {
    local archive="$downloaddir/inih-$pkgver.tar.gz"

    download \
        "https://github.com/benhoyt/inih/archive/refs/tags/$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        9c15fa751bb8093d042dae1b9f125eb45198c32c6704cd5481ccde460d4f8151 \
        "$archive"
    extract "$archive" "$srcdir/inih"
}

build() {
    log "Configuring inih"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/inih" \
            --prefix=/usr \
            --libdir=lib \
            --buildtype=release \
            -Ddefault_library=shared \
            -Dwith_INIReader=false \
            -Dtests=false

    log "Building inih"
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    package_keep /usr/lib/libinih.so.0
}

recipe_main "$@"
