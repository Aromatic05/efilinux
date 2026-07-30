#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=mdadm
pkgver=4.6
sysroot=false

depends=(glibc udev)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/mdadm-$pkgver.tar.gz"
    download \
        "https://git.kernel.org/pub/scm/utils/mdadm/mdadm.git/snapshot/mdadm-mdadm-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 202a7525e6f2b44395a9ef2c561082c7d6d8204e9addfe3f6268bfb141efc093 "$archive"
    extract "$archive" "$srcdir/mdadm"
}

build() {
    make -C "$srcdir/mdadm" -j"$EFILINUX_JOBS" \
        CC="$CC" \
        CXFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        VERSION="$pkgver" \
        BINDIR=/usr/bin \
        UDEVDIR=/usr/lib/udev \
        CHECK_RUN_DIR=0 \
        all
    make -C "$srcdir/mdadm" \
        DESTDIR="$develdir" \
        BINDIR=/usr/bin \
        UDEVDIR=/usr/lib/udev \
        STRIP= \
        install-bin install-udev
    install -Dm0644 /dev/null "$develdir/etc/mdadm.conf"
}

devel() {
    rm -rf "$develdir/usr/share/man"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /etc/mdadm.conf \
        /usr/bin/mdadm \
        /usr/bin/mdmon \
        /usr/lib/udev/rules.d/
}

recipe_main "$@"
