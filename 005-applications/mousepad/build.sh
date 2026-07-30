#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=mousepad
pkgver=0.6.5
depends=(glib glibc gtk3 gtksourceview4 xfce)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/mousepad-$pkgver.tar.xz"
    download "https://archive.xfce.org/src/apps/mousepad/0.6/mousepad-$pkgver.tar.xz" "$archive"
    checksum sha256 21762bc8c3c4f120a4a509ce39f4a5a58dbc10e3f0da66cdc6d9a8c735fff2ac "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-debug
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin"; }

package() {
    local -a keep=(/usr/bin/mousepad /usr/share/applications/ /usr/share/glib-2.0/schemas/ /usr/share/icons/hicolor/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
