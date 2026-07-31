#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=mbedtls2
pkgver=2.28.10
depends=(glibc)
builddepends=()
makedepends=(cmake gcc ninja)
prepare() {
    local archive="$downloaddir/mbedtls-$pkgver.tar.gz"
    download "https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 0f2e0525903a89ae1d39ce439d858be66933bda54c5b6102b72a29ed8fe7c088 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DENABLE_PROGRAMS=OFF \
        -DENABLE_TESTING=OFF \
        -DUSE_STATIC_MBEDTLS_LIBRARY=OFF \
        -DUSE_SHARED_MBEDTLS_LIBRARY=ON \
        -DMBEDTLS_FATAL_WARNINGS=OFF \
        -DENABLE_ZLIB_SUPPORT=OFF \
        -DUSE_PKCS11_HELPER_LIBRARY=OFF
    target_cmake_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libmbedcrypto.so.*'
    package_add_library_family keep 'libmbedtls.so.*'
    package_add_library_family keep 'libmbedx509.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
