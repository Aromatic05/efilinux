#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=readline
pkgver=8.2

depends=(glibc ncurses)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/readline-$pkgver.tar.gz"
    download "https://ftp.gnu.org/gnu/readline/readline-$pkgver.tar.gz" "$archive"
    checksum sha256 3feb7171f16a84ee82ca18a36d7b9be109a52c04f492a053331d7d1095007c35 "$archive"
    extract "$archive" "$srcdir/readline"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/readline/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static
    make -j"$EFILINUX_JOBS" SHLIB_LIBS=-lncursesw
    make DESTDIR="$develdir" SHLIB_LIBS=-lncursesw install
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libreadline.so.8*'
    package_add_library_family keep 'libhistory.so.8*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
