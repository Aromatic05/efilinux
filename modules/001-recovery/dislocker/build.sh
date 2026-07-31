#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=dislocker
pkgver=0.7.3
depends=(fuse2 glibc mbedtls2)
builddepends=()
makedepends=(cmake gcc gzip ninja pkg-config)
prepare() {
    local archive="$downloaddir/dislocker-$pkgver.tar.gz"
    download "https://github.com/Aorimn/dislocker/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 8d5275577c44f2bd87f6e05dd61971a71c0e56a9cbedf000bd38deadd8b6c1e6 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/cmake-read-mbedtls-version.patch" \
        "$srcdir/cmake-read-mbedtls-version.patch"
    input_file "$recipedir/files/c23-true-identifier.patch" \
        "$srcdir/c23-true-identifier.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/cmake-read-mbedtls-version.patch"
    patch -d "$srcdir/source" -Np1 -i "$srcdir/c23-true-identifier.patch"
    sed -i 's/set (VERSION_RELEASE 2)/set (VERSION_RELEASE 3)/' "$srcdir/source/CMakeLists.txt"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_SKIP_RPATH=ON \
        -DCMAKE_DISABLE_FIND_PACKAGE_Ruby=TRUE \
        -DPOLARSSL_INCLUDE_DIRS="$EFILINUX_SYSROOT/usr/include" \
        -DPOLARSSL_LIBRARIES="$EFILINUX_SYSROOT/usr/lib/libmbedcrypto.so" \
        -DFUSE_INCLUDE_DIRS="$EFILINUX_SYSROOT/usr/include" \
        -DFUSE_LIBRARIES="$EFILINUX_SYSROOT/usr/lib/libfuse.so" \
        -Dbindir=/usr/bin \
        -Dlibdir=/usr/lib \
        -Dmandir=/usr/share/man
    target_cmake_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }
package() {
    local -a keep=(
        /usr/bin/dislocker
        /usr/bin/dislocker-bek
        /usr/bin/dislocker-file
        /usr/bin/dislocker-fuse
        /usr/bin/dislocker-metadata
    )
    package_add_library_family keep 'libdislocker.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
