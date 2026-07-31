#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libssh
pkgver=0.11.5
depends=(glibc openssl zlib)
builddepends=()
makedepends=(cmake gcc ninja pkg-config)
prepare() {
    local archive="$downloaddir/libssh-$pkgver.tar.xz"
    download "https://www.libssh.org/files/0.11/libssh-$pkgver.tar.xz" "$archive"
    checksum sha256 6898ba9dd836d618b71dc7a4bb786a502c173cef5cafbf20fe5e0567ba4ea30c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIB=OFF \
        -DWITH_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DWITH_SFTP=ON \
        -DWITH_SERVER=OFF \
        -DWITH_GSSAPI=OFF \
        -DWITH_PCAP=OFF \
        -DWITH_ZLIB=ON \
        -DWITH_GCRYPT=OFF \
        -DWITH_SYMBOL_VERSIONING=ON \
        -DWITH_NACL=OFF \
        -DWITH_BENCHMARKS=OFF \
        -DWITH_FUZZ=OFF \
        -DWITH_DOC=OFF
    target_cmake_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libssh.so.4*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
