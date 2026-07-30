#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libsndfile
pkgver=1.2.2

depends=(
    glibc
)
builddepends=()
makedepends=(
    cmake
    gcc
    ninja
    pkg-config
)

prepare() {
    local archive="$downloaddir/libsndfile-$pkgver.tar.xz"

    download \
        "https://github.com/libsndfile/libsndfile/releases/download/$pkgver/libsndfile-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        3799ca9924d3125038880367bf1468e53a1b7e3686a934f098b7e1d286cdb80e \
        "$archive"
    extract "$archive" "$srcdir/libsndfile"
}

build() {
    cmake -S "$srcdir/libsndfile" -B "$builddir" -G Ninja \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_SYSROOT="$EFILINUX_SYSROOT" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_PROGRAMS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_REGTEST=OFF \
        -DBUILD_TESTING=OFF \
        -DENABLE_EXTERNAL_LIBS=OFF \
        -DENABLE_MPEG=OFF \
        -DENABLE_EXPERIMENTAL=OFF \
        -DENABLE_CPACK=OFF \
        -DENABLE_BOW_DOCS=OFF \
        -DENABLE_PACKAGE_CONFIG=ON
    cmake --build "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" cmake --install "$builddir"
}

devel() {
    find "$develdir" -type f -name '*.a' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local library relative
    local -a keep=()
    local -a libraries=()

    mapfile -d '' -t libraries < <(
        find "$pkgdir/usr/lib" -maxdepth 1 \
            \( -type f -o -type l \) \
            -name 'libsndfile.so.1*' \
            -print0 | LC_ALL=C sort -z
    )
    ((${#libraries[@]} > 0)) || die "libsndfile runtime library is missing"
    for library in "${libraries[@]}"; do
        relative=/${library#"$pkgdir/"}
        keep+=("$relative")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
