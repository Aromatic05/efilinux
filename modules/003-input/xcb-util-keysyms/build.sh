#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xcb-util-keysyms
pkgver=0.4.1
depends=(glibc xorg)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/xcb-util-keysyms-$pkgver.tar.xz"
    download "https://xcb.freedesktop.org/dist/xcb-util-keysyms-$pkgver.tar.xz" "$archive"
    checksum sha256 7c260a5294412aed429df1da2f8afd3bd07b7cba3fec772fba15a613a6d5c638 "$archive"
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
    package_add_library_family keep 'libxcb-keysyms.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
