#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=fuse
pkgver=3.18.2

depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/fuse-$pkgver.tar.gz"
    download \
        "https://github.com/libfuse/libfuse/releases/download/fuse-$pkgver/fuse-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 f01de85717e20adf5f98aff324acd85dd73d61a5ca3834d573dcf0bd6e54a298 "$archive"
    extract "$archive" "$srcdir/fuse"
}

build() {
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/fuse" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dexamples=false \
            -Dtests=false \
            -Duseroot=false \
            -Dudevrulesdir=/usr/lib/udev/rules.d
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    chmod 4755 "$develdir/usr/bin/fusermount3"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/bin/fusermount3)
    package_add_library_family keep 'libfuse3.so.4*'
    package_add_library_family keep 'libfuse3.so.3*'
    [[ ! -f "$pkgdir/etc/fuse.conf" ]] || keep+=(/etc/fuse.conf)
    package_keep "${keep[@]}"
}

recipe_main "$@"
