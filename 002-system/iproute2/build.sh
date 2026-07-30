#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=iproute2
pkgver=7.1.0
sysroot=false

depends=(glibc libcap)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/iproute2-$pkgver.tar.xz"

    download \
        "https://mirrors.edge.kernel.org/pub/linux/utils/net/iproute2/iproute2-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 fd9fa1b95809417157ca83dd72957e3261bdbce896353cb936f80af0b33a4b5c "$archive"
    extract "$archive" "$srcdir/iproute2"
}

build() {
    cp -a "$srcdir/iproute2/." "$builddir/"
    cd "$builddir"
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        ./configure

    log "Building iproute2"
    make -j"$EFILINUX_JOBS" \
        PREFIX=/usr SBINDIR=/usr/bin LIBDIR=/usr/lib \
        CONFDIR=/etc/iproute2 NETNS_RUN_DIR=/run/netns
    make DESTDIR="$develdir" install \
        PREFIX=/usr SBINDIR=/usr/bin LIBDIR=/usr/lib \
        CONFDIR=/etc/iproute2 NETNS_RUN_DIR=/run/netns
}

devel() {
    rm -rf "$develdir/usr/share/man" "$develdir/usr/share/doc"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/ip \
        /usr/bin/ss \
        /usr/bin/bridge \
        /usr/bin/tc \
        /usr/bin/nstat \
        /usr/bin/rtmon
}

recipe_main "$@"
