#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=pciutils
pkgver=3.14.0
depends=(glibc zlib)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/pciutils-$pkgver.tar.gz"
    download "https://mj.ucw.cz/download/linux/pci/pciutils-$pkgver.tar.gz" "$archive"
    checksum sha256 a9327c42dcbd48704cf1af91f0661743178415ccac9a7e86c78b6a2bafaf4720 "$archive"
    extract "$archive" "$srcdir/pciutils"
}

build() {
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        make -C "$srcdir/pciutils" -j"$EFILINUX_JOBS" \
            PREFIX=/usr LIBDIR=/usr/lib SHARED=yes ZLIB=yes DNS=no IDSDIR=no
    make -C "$srcdir/pciutils" PREFIX=/usr LIBDIR=/usr/lib DESTDIR="$develdir" \
        SHARED=yes ZLIB=yes DNS=no IDSDIR=no install install-lib
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }
package() {
    local -a keep=(/usr/bin/lspci /usr/bin/setpci)
    package_add_library_family keep 'libpci.so.3*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
