#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libgcrypt
pkgver=1.12.2

depends=(glibc libgpg-error)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libgcrypt-$pkgver.tar.bz2"
    download "https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-$pkgver.tar.bz2" "$archive"
    checksum sha256 7ce33c2492221a0436f96a8500215e9f3e3dcb5fd26a757cd415e7a843babd5e "$archive"
    extract "$archive" "$srcdir/libgcrypt"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/libgcrypt/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static \
            --disable-doc \
            --disable-tests \
            --disable-jent-support
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libgcrypt.so.20*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
