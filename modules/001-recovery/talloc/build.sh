#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=talloc
pkgver=2.4.4
depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config python3)

prepare() {
    local archive="$downloaddir/talloc-$pkgver.tar.gz"
    download "https://download.samba.org/pub/talloc/talloc-$pkgver.tar.gz" "$archive"
    checksum sha256 55e47994018c13743485544e7206780ffbb3c8495e704a99636503e6e77abf59 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local compiler
    compiler=$(target_compiler_wrapper gcc)
    (
        cd "$srcdir/source"
        CC="$compiler" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PKG_CONFIG_PATH= \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            ./configure \
                --prefix=/usr \
                --libdir=/usr/lib \
                --disable-python \
                --without-gettext \
                --disable-rpath \
                --disable-rpath-install \
                --disable-rpath-private-install \
                --disable-warnings-as-errors
        make -j"$EFILINUX_JOBS"
        make DESTDIR="$develdir" install
    )
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libtalloc.so.*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
