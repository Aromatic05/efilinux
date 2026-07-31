#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=qemu-img
pkgver=11.0.3
depends=(attr bzip2 gcc-libs glib glibc libgcrypt libssh xz zlib zstd)
builddepends=()
makedepends=(gcc g++ meson ninja perl pkg-config python3)

prepare() {
    local archive="$downloaddir/qemu-$pkgver.tar.xz"
    download "https://download.qemu.org/qemu-$pkgver.tar.xz" "$archive"
    checksum sha256 da5fcffc32762820568b828ed430a728864d34d50b6d2f30358597760cbb0523 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local cc cxx
    cc=$(target_compiler_wrapper gcc)
    cxx=$(target_compiler_wrapper g++)

    (
        cd "$builddir"
        CC="$cc" \
        CXX="$cxx" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PKG_CONFIG_PATH= \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            "$srcdir/source/configure" \
                --prefix=/usr \
                --bindir=/usr/bin \
                --libdir=/usr/lib \
                --datadir=/usr/share \
                --docdir=/usr/share/doc/qemu \
                --mandir=/usr/share/man \
                --cc="$cc" \
                --cxx="$cxx" \
                --host-cc=/usr/bin/gcc \
                --python=/usr/bin/python3 \
                --ninja=/usr/bin/ninja \
                --disable-download \
                --without-default-features \
                --disable-system \
                --disable-user \
                --enable-tools \
                --enable-attr \
                --enable-bzip2 \
                --enable-gcrypt \
                --enable-libssh \
                --enable-zstd
        ninja -j"$EFILINUX_JOBS"
        DESTDIR="$develdir" ninja install
    )
}

check() {
    grep -Fxq 'TARGET_DIRS=' "$builddir/config-host.mak" ||
        die "QEMU block-tools build unexpectedly enabled emulation targets"
    ! grep -Eq '^#define CONFIG_TCG([[:space:]]|$)' "$builddir/config-host.h" ||
        die "QEMU block-tools build unexpectedly enabled TCG"
    [[ -x "$develdir/usr/bin/qemu-img" && -x "$develdir/usr/bin/qemu-nbd" ]] ||
        die "QEMU block tools are missing"
    if find "$develdir/usr/bin" -maxdepth 1 -type f \
            \( -name 'qemu-system-*' -o -name 'qemu-*-static' \) \
            -print -quit | grep -q .; then
        die "QEMU block-tools package contains an emulator binary"
    fi
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/qemu-img \
        /usr/bin/qemu-nbd
}

recipe_main "$@"
