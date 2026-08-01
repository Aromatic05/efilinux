#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=nss
pkgver=3.95-1
depends=(glibc nspr sqlite zlib)
builddepends=()
makedepends=()

prepare() {
    local archive="$downloaddir/nss-$pkgver-x86_64.pkg.tar.zst"
    download "https://archive.archlinux.org/packages/n/nss/nss-$pkgver-x86_64.pkg.tar.zst" "$archive"
    checksum sha256 6a2c4a1ff8baa0315edf3826b26754bf3b470d3ad43d1056ff157091b6e64cf1 "$archive"
}

build() {
    local library
    mkdir -p "$srcdir/unpacked" "$develdir/usr/lib"
    tar -xf "$downloaddir/nss-$pkgver-x86_64.pkg.tar.zst" -C "$srcdir/unpacked"
    for library in \
        libfreebl3.so \
        libfreeblpriv3.so \
        libnss3.so \
        libnsssysinit.so \
        libnssutil3.so \
        libsmime3.so \
        libsoftokn3.so \
        libssl3.so; do
        install -m0755 "$srcdir/unpacked/usr/lib/$library" "$develdir/usr/lib/"
    done
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    package_keep \
        /usr/lib/libfreebl3.so \
        /usr/lib/libfreeblpriv3.so \
        /usr/lib/libnss3.so \
        /usr/lib/libnsssysinit.so \
        /usr/lib/libnssutil3.so \
        /usr/lib/libsmime3.so \
        /usr/lib/libsoftokn3.so \
        /usr/lib/libssl3.so
}

recipe_main "$@"
