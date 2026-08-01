#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=nspr
pkgver=4.35-1
depends=(glibc)
builddepends=()
makedepends=()

prepare() {
    local archive="$downloaddir/nspr-$pkgver-x86_64.pkg.tar.zst"
    download "https://archive.archlinux.org/packages/n/nspr/nspr-$pkgver-x86_64.pkg.tar.zst" "$archive"
    checksum sha256 b54002742ef1537af0331db1272c268edc7c35448fb353dd5d9f6f5497b19c49 "$archive"
}

build() {
    mkdir -p "$srcdir/unpacked" "$develdir/usr/lib"
    tar -xf "$downloaddir/nspr-$pkgver-x86_64.pkg.tar.zst" -C "$srcdir/unpacked"
    install -m0755 "$srcdir/unpacked/usr/lib/libnspr4.so" "$develdir/usr/lib/"
    install -m0755 "$srcdir/unpacked/usr/lib/libplc4.so" "$develdir/usr/lib/"
    install -m0755 "$srcdir/unpacked/usr/lib/libplds4.so" "$develdir/usr/lib/"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    package_keep /usr/lib/libnspr4.so /usr/lib/libplc4.so /usr/lib/libplds4.so
}

recipe_main "$@"
