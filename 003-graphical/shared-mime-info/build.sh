#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=shared-mime-info
pkgver=2.5.1

depends=(gcc-libs glib glibc libxml2)
builddepends=()
makedepends=(gcc g++ meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/shared-mime-info-$pkgver.tar.bz2"
    download \
        "https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/$pkgver/shared-mime-info-$pkgver.tar.bz2" \
        "$archive"
    checksum sha256 b75b420da9b0be9a3d99b1bee6ed87957b56ab54583ac1a97fbd0dc98ddddb25 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dupdate-mimedb=false \
        -Dbuild-tools=true \
        -Dbuild-translations=false \
        -Dbuild-tests=false \
        -Dbuild-spec=false
    target_meson_install "$builddir" "$develdir"
}

devel() {
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/update-mime-database \
        /usr/share/mime/
}

recipe_main "$@"
