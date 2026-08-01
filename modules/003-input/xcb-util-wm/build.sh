#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xcb-util-wm
pkgver=0.4.2
depends=(glibc xorg)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/xcb-util-wm-$pkgver.tar.xz"
    download "https://xcb.freedesktop.org/dist/xcb-util-wm-$pkgver.tar.xz" "$archive"
    checksum sha256 62c34e21d06264687faea7edbf63632c9f04d55e72114aa4a57bb95e4f888a0b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --disable-devel-docs
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libxcb-icccm.so.4*'
    package_add_library_family keep 'libxcb-ewmh.so.2*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
