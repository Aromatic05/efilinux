#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=lm-sensors
pkgver=3.6.2
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/lm-sensors-$pkgver.tar.gz"
    download "https://github.com/lm-sensors/lm-sensors/archive/refs/tags/V3-6-2.tar.gz" "$archive"
    checksum sha256 c6a0587e565778a40d88891928bf8943f27d353f382d5b745a997d635978a8f0 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" user \
        PREFIX=/usr ETCDIR=/etc LIBDIR=/usr/lib BINDIR=/usr/bin SBINDIR=/usr/bin \
        MANDIR=/usr/share/man BUILD_STATIC_LIB=0 BUILD_SHARED_LIB=1 \
        CC="$CC" AR=/usr/bin/ar CFLAGS="$CFLAGS" EXLDFLAGS="$LDFLAGS"
    make -C "$srcdir/source" user_install \
        PREFIX=/usr ETCDIR=/etc LIBDIR=/usr/lib BINDIR=/usr/bin SBINDIR=/usr/bin \
        MANDIR=/usr/share/man BUILD_STATIC_LIB=0 BUILD_SHARED_LIB=1 \
        DESTDIR="$develdir" CC="$CC" AR=/usr/bin/ar \
        CFLAGS="$CFLAGS" EXLDFLAGS="$LDFLAGS"
}
devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }
package() {
    local -a keep=(/usr/bin/sensors /etc/sensors3.conf)
    package_add_library_family keep 'libsensors.so.5*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
