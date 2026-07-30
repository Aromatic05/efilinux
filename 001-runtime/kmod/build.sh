#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=kmod
pkgver=34.2

depends=(
    glibc
    xz
    zlib
    zstd
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
    local archive="$downloaddir/kmod-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        5a5d5073070cc7e0c7a7a3c6ec2a0e1780850c8b47b3e3892226b93ffcb9cb54 \
        "$archive"
    extract "$archive" "$srcdir/kmod"
}

build() {
    log "Configuring Kmod"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig" \
        "$srcdir/kmod/configure" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static \
            --disable-manpages \
            --with-zstd \
            --with-xz \
            --with-zlib \
            --without-openssl

    log "Building Kmod"
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

    library_target=$(readlink -- "$pkgdir/usr/lib/libkmod.so.2")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "Kmod SONAME target is missing: $library_target"

    package_keep \
        /usr/bin/kmod \
        /usr/bin/depmod \
        /usr/bin/insmod \
        /usr/bin/lsmod \
        /usr/bin/modinfo \
        /usr/bin/modprobe \
        /usr/bin/rmmod \
        /usr/lib/libkmod.so.2 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
