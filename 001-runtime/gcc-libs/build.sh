#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=gcc-libs
pkgver=16.1.0

depends=(
    glibc
)
builddepends=(
    linux-headers
)
makedepends=(
    bison
    flex
    g++
    gcc
    make
    perl
)

prepare() {
    local archive="$downloaddir/gcc-$pkgver.tar.xz"

    download \
        "https://ftpmirror.gnu.org/gcc/gcc-$pkgver/gcc-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79 \
        "$archive"
    extract "$archive" "$srcdir/gcc"
}

build() {
    local build_triplet
    local target_flags=$CFLAGS

    build_triplet=$($CC -dumpmachine)

    log "Configuring GCC libraries"
    cd "$builddir"
    env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
        "$srcdir/gcc/configure" \
        --build="$build_triplet" \
        --host="$build_triplet" \
        --target="$build_triplet" \
        --prefix=/usr \
        --libdir=/usr/lib \
        --with-sysroot="$EFILINUX_SYSROOT" \
        --with-native-system-header-dir=/usr/include \
        --enable-languages=c,c++ \
        --disable-bootstrap \
        --disable-multilib \
        --disable-nls \
        --disable-werror \
        --disable-libstdcxx-pch \
        --disable-libsanitizer

    log "Building GCC ABI libraries"
    env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
        make -j"$EFILINUX_JOBS" \
        CFLAGS_FOR_TARGET="$target_flags" \
        CXXFLAGS_FOR_TARGET="$target_flags" \
        all-target-libgcc all-target-libstdc++-v3
    env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
        make \
        DESTDIR="$develdir" \
        CFLAGS_FOR_TARGET="$target_flags" \
        CXXFLAGS_FOR_TARGET="$target_flags" \
        install-target-libgcc install-target-libstdc++-v3

    if [[ -d "$develdir/usr/lib64" ]]; then
        mkdir -p "$develdir/usr/lib"
        cp -a --remove-destination "$develdir/usr/lib64/." "$develdir/usr/lib/"
        rm -rf "$develdir/usr/lib64"
    fi

    [[ -f "$develdir/usr/lib/libgcc_s.so.1" ]] || \
        die "GCC libraries did not install libgcc_s.so.1"
    [[ -L "$develdir/usr/lib/libstdc++.so.6" ]] || \
        die "GCC libraries did not install libstdc++.so.6"
    [[ ! -d "$develdir/usr/bin" ]] || \
        die "GCC compiler programs leaked into the GCC libraries devel tree"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local libstdcxx_target

    libstdcxx_target=$(readlink -- "$pkgdir/usr/lib/libstdc++.so.6")
    [[ -f "$pkgdir/usr/lib/$libstdcxx_target" ]] || \
        die "GCC libraries SONAME target is missing: $libstdcxx_target"

    package_keep \
        /usr/lib/libgcc_s.so.1 \
        /usr/lib/libstdc++.so.6 \
        "/usr/lib/$libstdcxx_target"
}

recipe_main "$@"
