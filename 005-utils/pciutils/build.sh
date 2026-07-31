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
    checksum sha256 e31c79722dbbe9d2906b92996ce295268e54d4342fefe3ff476caa613e51be2a "$archive"
    extract "$archive" "$srcdir/pciutils"
}

build() {
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        make -C "$srcdir/pciutils" -j"$EFILINUX_JOBS" \
            PREFIX=/usr LIBDIR=/usr/lib SHARED=yes ZLIB=yes DNS=no IDSDIR=/usr/share/hwdata
    make -C "$srcdir/pciutils" PREFIX=/usr LIBDIR=/usr/lib DESTDIR="$develdir" \
        SHARED=yes ZLIB=yes DNS=no IDSDIR=/usr/share/hwdata install install-lib
    mv "$develdir/usr/sbin/setpci" "$develdir/usr/bin/setpci"
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }
package() {
    local -a keep=(/usr/bin/lspci /usr/bin/setpci /usr/share/hwdata/pci.ids.gz)
    package_add_library_family keep 'libpci.so.3*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
