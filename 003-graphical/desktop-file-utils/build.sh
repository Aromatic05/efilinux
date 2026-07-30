#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=desktop-file-utils
pkgver=0.28

depends=(glib glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/desktop-file-utils-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/xdg/desktop-file-utils/-/archive/$pkgver/desktop-file-utils-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 379ecbc1354d0c052188bdf5dbbc4a020088ad3f9cab54487a5852d1743a4f3b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir"
    target_meson_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/
}

recipe_main "$@"
