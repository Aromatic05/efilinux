#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libpcap
pkgver=1.10.6
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libpcap-$pkgver.tar.xz"
    download "https://www.tcpdump.org/release/libpcap-$pkgver.tar.xz" "$archive"
    checksum sha256 ec97d1206bdd19cb6bdd043eaa9f0037aa732262ec68e070fd7c7b5f834d5dfc "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --disable-remote \
        --disable-usb \
        --disable-bluetooth \
        --disable-dbus \
        --disable-rdma \
        --without-libnl
    target_make_install "$builddir" "$develdir"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libpcap.so.*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
