#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=readline
pkgver=8.3

depends=(glibc ncurses)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/readline-$pkgver.tar.gz"
    download "https://ftp.gnu.org/gnu/readline/readline-$pkgver.tar.gz" "$archive"
    checksum sha256 fe5383204467828cd495ee8d1d3c037a7eba1389c22bc6a041f627976f9061cc "$archive"
    extract "$archive" "$srcdir/readline"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    sed -i '/MV.*old/d' "$srcdir/readline/Makefile.in"
    sed -i '/{OLDSUFF}/c:' "$srcdir/readline/support/shlib-install"
    sed -i 's/-Wl,-rpath,[^ ]*//' "$srcdir/readline/support/shobj-conf"
    sed -e '270a\
         else\
           chars_avail = 1;' \
        -e '288i\   result = -1;' \
        -i.orig "$srcdir/readline/input.c"
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
            --disable-static \
            --with-curses
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
