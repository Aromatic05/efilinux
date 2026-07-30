#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=ristretto
pkgver=0.13.4
depends=(gdk-pixbuf glib glibc gtk3 libexif xfce)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/ristretto-$pkgver.tar.xz"
    download "https://archive.xfce.org/src/apps/ristretto/0.13/ristretto-$pkgver.tar.xz" "$archive"
    checksum sha256 a84ef8cb80638681d9b9ef09cddff86a5d7a0e028603b4a601cf0ff6c2869ce8 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-debug
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin"; }

package() {
    local -a keep=(/usr/bin/ristretto /usr/share/applications/ /usr/share/icons/hicolor/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
