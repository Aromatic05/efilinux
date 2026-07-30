#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=hicolor-icon-theme
pkgver=0.18
sysroot=false

depends=()
builddepends=()
makedepends=(meson ninja)

prepare() {
    local archive="$downloaddir/hicolor-icon-theme-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/xdg/default-icon-theme/-/archive/v$pkgver/default-icon-theme-v$pkgver.tar.gz" \
        "$archive"
    checksum sha256 9227ec70c6b59a715a18dcedbed590cb08edc9eadb73fb2b0a57034e15c18f36 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir"
    target_meson_install "$builddir" "$develdir"
}

package() {
    package_keep /usr/share/icons/hicolor/
}

recipe_main "$@"
