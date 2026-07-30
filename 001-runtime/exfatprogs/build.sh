#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=exfatprogs
pkgver=1.4.2

depends=(
    glibc
)
builddepends=(
    linux-headers
)
makedepends=(
    gcc
    make
    pkg-config
)

prepare() {
    local archive="$downloaddir/exfatprogs-$pkgver.tar.xz"

    download \
        "https://github.com/exfatprogs/exfatprogs/releases/download/$pkgver/exfatprogs-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        47c7c8ddeccbf50d39b903353f2cb3df79134367a4fd764fe2ce3755ff5877bf \
        "$archive"
    extract "$archive" "$srcdir/exfatprogs"
}

build() {
    log "Configuring exfatprogs"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/exfatprogs/configure" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --disable-static

    log "Building exfatprogs"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/exfatlabel \
        /usr/bin/fsck.exfat \
        /usr/bin/mkfs.exfat \
        /usr/bin/tune.exfat
}

recipe_main "$@"
