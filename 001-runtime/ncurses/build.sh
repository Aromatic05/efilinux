#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=ncurses
pkgver=6.6

depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/ncurses-$pkgver.tar.gz"
    download "https://ftp.gnu.org/gnu/ncurses/ncurses-$pkgver.tar.gz" "$archive"
    checksum sha256 355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11 "$archive"
    extract "$archive" "$srcdir/ncurses"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/ncurses/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --with-shared \
            --without-normal \
            --without-debug \
            --enable-widec \
            --enable-pc-files \
            --with-pkg-config-libdir=/usr/lib/pkgconfig \
            --with-default-terminfo-dir=/usr/share/terminfo \
            --with-terminfo-dirs=/usr/share/terminfo \
            --without-ada \
            --without-cxx-binding \
            --without-tests
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    local library
    for library in ncurses form panel menu; do
        printf 'INPUT(-l%sw)\n' "$library" > "$develdir/usr/lib/lib$library.so"
        ln -sf "${library}w.pc" "$develdir/usr/lib/pkgconfig/$library.pc"
    done
    ln -sf libncurses.so "$develdir/usr/lib/libcurses.so"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local name path
    local -a keep=(
        /usr/bin/captoinfo
        /usr/bin/infocmp
        /usr/bin/infotocap
        /usr/bin/reset
        /usr/bin/tabs
        /usr/bin/tic
        /usr/bin/toe
        /usr/bin/tput
        /usr/bin/tset
    )
    package_add_library_family keep 'libncursesw.so.6*'
    for name in linux xterm xterm-256color screen screen-256color tmux tmux-256color; do
        path=$(find "$pkgdir/usr/share/terminfo" -type f -name "$name" -print -quit)
        [[ -n $path ]] || die "required terminfo entry was not installed: $name"
        keep+=("/${path#"$pkgdir/"}")
    done
    package_keep "${keep[@]}"
}

recipe_main "$@"
