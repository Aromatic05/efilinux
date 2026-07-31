#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=poppler
pkgver=26.07.0

depends=(
    cairo
    fontconfig
    freetype
    gcc-libs
    glib
    glibc
    libjpeg-turbo
    libpng
    openjpeg
    zlib
)
builddepends=()
makedepends=(cmake gcc ninja pkg-config)

prepare() {
    local archive="$downloaddir/poppler-$pkgver.tar.xz"

    download "https://poppler.freedesktop.org/poppler-$pkgver.tar.xz" "$archive"
    checksum sha256 304832f48f8a47fdca90c6b6d1f684e68f37c10c9a0726f345f4ca9df4ca01e2 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_SHARED_LIBS=ON \
        -DENABLE_UNSTABLE_API_ABI_HEADERS=OFF \
        -DBUILD_GTK_TESTS=OFF \
        -DBUILD_QT5_TESTS=OFF \
        -DBUILD_QT6_TESTS=OFF \
        -DBUILD_CPP_TESTS=OFF \
        -DBUILD_MANUAL_TESTS=OFF \
        -DENABLE_BOOST=OFF \
        -DENABLE_UTILS=OFF \
        -DENABLE_CPP=OFF \
        -DENABLE_GLIB=ON \
        -DENABLE_GOBJECT_INTROSPECTION=OFF \
        -DENABLE_GTK_DOC=OFF \
        -DENABLE_QT5=OFF \
        -DENABLE_QT6=OFF \
        -DENABLE_LIBOPENJPEG=ON \
        -DENABLE_LIBJPEG=ON \
        -DENABLE_LCMS=OFF \
        -DENABLE_LIBCURL=OFF \
        -DENABLE_LIBTIFF=OFF \
        -DENABLE_NSS3=OFF \
        -DENABLE_GPGME=OFF \
        -DENABLE_PGP_SIGNATURES=OFF \
        -DRUN_GPERF_IF_PRESENT=OFF \
        -DINSTALL_GLIB_DEMO=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()

    package_add_library_family keep 'libpoppler.so.*'
    package_add_library_family keep 'libpoppler-glib.so.8*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
