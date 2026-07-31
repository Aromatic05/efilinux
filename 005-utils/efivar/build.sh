#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=efivar
pkgver=39
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/efivar-$pkgver.tar.gz"
    download "https://github.com/rhboot/efivar/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 c9edd15f2eeeea63232f3e669a48e992c7be9aff57ee22672ac31f5eca1609a6 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" \
        ENABLE_DOCS=0 PREFIX=/usr LIBDIR=/usr/lib BINDIR=/usr/bin \
        PCDIR=/usr/lib/pkgconfig CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        HOSTCC=/usr/bin/gcc HOSTCCLD=/usr/bin/gcc \
        HOST_CPPFLAGS= HOST_CFLAGS='-O2 -g0' HOST_LDFLAGS=
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    make -C "$srcdir/source" install \
        ENABLE_DOCS=0 PREFIX=/usr LIBDIR=/usr/lib BINDIR=/usr/bin \
        PCDIR=/usr/lib/pkgconfig DESTDIR="$develdir" \
        CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        HOSTCC=/usr/bin/gcc HOSTCCLD=/usr/bin/gcc \
        HOST_CPPFLAGS= HOST_CFLAGS='-O2 -g0' HOST_LDFLAGS=
}
devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }
package() {
    local -a keep=(/usr/bin/efivar /usr/bin/efisecdb)
    package_add_library_family keep 'libefivar.so.1*'
    package_add_library_family keep 'libefiboot.so.1*'
    package_add_library_family keep 'libefisec.so.1*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
