#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=device-mapper
pkgver=2.03.41

depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/lvm2-$pkgver.tgz"
    download "https://sourceware.org/ftp/lvm2/LVM2.$pkgver.tgz" "$archive"
    checksum sha256 d58011b845df8ec13816ca13ea6c39d4cb3d038cd2d7d387acdf5681ad7d6637 "$archive"
    extract "$archive" "$srcdir/lvm2"
}

build() {
    cd "$builddir"
    CONFIG_SHELL=/bin/bash \
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/lvm2/configure" \
            --prefix=/usr \
            --sbindir=/usr/bin \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --enable-pkgconfig \
            --disable-readline \
            --disable-selinux \
            --disable-udev_sync \
            --disable-udev_rules \
            --disable-systemd-journal \
            --disable-use-lvmpolld \
            --without-systemd \
            --without-udev \
            --with-thin=none \
            --with-cache=none \
            --with-writecache=none \
            --with-default-dm-run-dir=/run
    make -j"$EFILINUX_JOBS" device-mapper
    make DESTDIR="$develdir" install_device-mapper
}

devel() {
    rm -rf "$develdir/usr/lib/systemd"
    find "$develdir" -type f -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/bin/dmsetup)
    package_add_library_family keep 'libdevmapper.so.1.02*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
