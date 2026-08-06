#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=newt
pkgver=0.52.25
depends=(glibc popt slang)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/newt-$pkgver.tar.gz"
    download "https://releases.pagure.org/newt/newt-$pkgver.tar.gz" "$archive"
    checksum sha256 ef0ca9ee27850d1a5c863bb7ff9aa08096c9ed312ece9087b30f3a426828de82 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    cp -a "$srcdir/source/." "$builddir/"
    (
        cd "$builddir"
        CC="$(target_compiler_wrapper gcc)" \
        CFLAGS="$CFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            ./configure \
                --prefix=/usr \
                --libdir=/usr/lib \
                --disable-nls \
                --without-gpm-support \
                --without-python \
                --without-tcl
    )
    make -C "$builddir" -j"$EFILINUX_JOBS" sharedlib
    make -C "$builddir" instroot="$develdir" install-sh
}
check() { [[ -f "$develdir/usr/lib/libnewt.so.0.52" ]] || die "Newt shared library is missing"; }
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libnewt.so.0.52*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
