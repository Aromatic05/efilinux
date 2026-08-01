#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=iperf3
pkgver=3.21
depends=(glibc openssl)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/iperf-$pkgver.tar.gz"
    download "https://github.com/esnet/iperf/releases/download/$pkgver/iperf-$pkgver.tar.gz" "$archive"
    checksum sha256 656e4405ebd620121de7ceca3eaf43a88f79ea1b857d041a6a0b1314801acdd8 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --disable-static \
        --enable-shared \
        --without-sctp \
        --with-openssl="$EFILINUX_SYSROOT/usr"
    target_make_install "$builddir" "$develdir"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    rm -rf "$develdir/usr/share/man"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/bin/iperf3)
    package_add_library_family keep 'libiperf.so.*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
