#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libblockdev
pkgver=3.5.0

depends=(cryptsetup e2fsprogs glib glibc keyutils kmod libbytesize libnvme mdadm udev util-linux)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libblockdev-$pkgver.tar.gz"
    download \
        "https://github.com/storaged-project/libblockdev/releases/download/$pkgver/libblockdev-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 bccd30e6b5d11504de60d9889ff6a2a25b07a4ec8f04070f2387e168301b3e3a "$archive"
    extract "$archive" "$srcdir/libblockdev"
}

build() {
    cd "$builddir"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/libblockdev/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-static \
            --disable-tests \
            --without-python3 \
            --without-gtk-doc \
            --with-crypto \
            --without-escrow \
            --without-dm \
            --without-lvm \
            --without-lvm-dbus \
            --without-mpath \
            --with-mdraid \
            --without-btrfs \
            --without-s390 \
            --without-nvdimm \
            --with-nvme \
            --without-smart \
            --without-smartmontools \
            --without-tools \
            --with-loop \
            --with-swap \
            --with-fs \
            --with-part
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir" -type f -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libblockdev.so.3*'
    package_add_library_family keep 'libbd_crypto.so.3*'
    package_add_library_family keep 'libbd_fs.so.3*'
    package_add_library_family keep 'libbd_loop.so.3*'
    package_add_library_family keep 'libbd_mdraid.so.3*'
    package_add_library_family keep 'libbd_nvme.so.3*'
    package_add_library_family keep 'libbd_part.so.3*'
    package_add_library_family keep 'libbd_swap.so.3*'
    package_add_library_family keep 'libbd_utils.so.3*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
