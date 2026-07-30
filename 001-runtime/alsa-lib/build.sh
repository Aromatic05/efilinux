#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=alsa-lib
pkgver=1.2.16.1

depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/alsa-lib-$pkgver.tar.bz2"
    download "https://www.alsa-project.org/files/pub/lib/alsa-lib-$pkgver.tar.bz2" "$archive"
    checksum sha256 f740db7f488255944ffd4428416ee3390a96742856916433df468c281436480e "$archive"
    extract "$archive" "$srcdir/alsa-lib"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/alsa-lib/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static \
            --disable-python
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libasound.so.2*'
    [[ ! -d "$pkgdir/usr/share/alsa" ]] || keep+=(/usr/share/alsa/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
