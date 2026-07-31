#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libvncserver
pkgver=0.9.15
depends=(glibc libjpeg-turbo libpng openssl zlib)
builddepends=()
makedepends=(cmake gcc ninja pkg-config)
prepare() {
    local archive="$downloaddir/libvncserver-$pkgver.tar.gz"
    download "https://github.com/LibVNC/libvncserver/archive/refs/tags/LibVNCServer-$pkgver.tar.gz" "$archive"
    checksum sha256 62352c7795e231dfce044beb96156065a05a05c974e5de9e023d688d8ff675d7 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SHARED_LIBS=ON \
        -DWITH_CLIENT=ON \
        -DWITH_SERVER=OFF \
        -DWITH_TIGHTVNC_FILETRANSFER=OFF \
        -DWITH_ZLIB=ON \
        -DWITH_JPEG=ON \
        -DWITH_PNG=ON \
        -DWITH_OPENSSL=ON \
        -DWITH_FFMPEG=OFF \
        -DWITH_GCRYPT=OFF \
        -DWITH_GNUTLS=OFF \
        -DWITH_SYSTEMD=OFF \
        -DWITH_SASL=OFF \
        -DWITH_LZO=OFF \
        -DWITH_PAM=OFF \
        -DWITH_EXAMPLES=OFF \
        -DWITH_TESTS=OFF \
        -DWITH_TOOLS=OFF
    target_cmake_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libvncclient.so.1*'
    package_add_library_family keep 'libvncserver.so.1*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
