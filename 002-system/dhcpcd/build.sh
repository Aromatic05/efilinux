#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=dhcpcd
pkgver=10.3.2
sysroot=false

depends=(glibc openssl udev)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/dhcpcd-$pkgver.tar.xz"

    download \
        "https://github.com/NetworkConfiguration/dhcpcd/releases/download/v$pkgver/dhcpcd-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 b6aa46932074906a9badef1bfe142b8aff9d041c2689e1ef8b74c12e9fd942bd "$archive"
    extract "$archive" "$srcdir/dhcpcd"
}

build() {
    cd "$srcdir/dhcpcd"
    log "Configuring dhcpcd"
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        ./configure \
            --prefix=/usr \
            --sbindir=/usr/bin \
            --libexecdir=/usr/lib/dhcpcd \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --dbdir=/var/lib/dhcpcd \
            --rundir=/run/dhcpcd \
            --mandir=/usr/share/man \
            --enable-privsep \
            --privsepuser=dhcpcd \
            --disable-auth \
            --with-udev

    log "Building dhcpcd"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    rm -rf "$develdir/usr/share/man"
    rm -f "$develdir/usr/share/dhcpcd/hooks/10-wpa_supplicant"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    package_keep \
        /usr/bin/dhcpcd \
        /usr/lib/dhcpcd/ \
        /usr/share/dhcpcd/
}

recipe_main "$@"
