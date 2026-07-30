#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libbytesize
pkgver=2.12

depends=(glibc gmp mpfr pcre2)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libbytesize-$pkgver.tar.gz"
    download \
        "https://github.com/storaged-project/libbytesize/releases/download/$pkgver/libbytesize-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 8356bac2cafd2f31f39bf1ad373cef8448cab08b817aeaee5c526d54e81c3c5a "$archive"
    extract "$archive" "$srcdir/libbytesize"
}

build() {
    cd "$builddir"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/libbytesize/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-static \
            --without-python3 \
            --without-gtk-doc \
            --without-tools
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir" -type f -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libbytesize.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
