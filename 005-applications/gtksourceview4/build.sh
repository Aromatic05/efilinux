#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=gtksourceview4
pkgver=4.8.4
depends=(glib glibc gtk3)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/gtksourceview-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/gtksourceview/4.8/gtksourceview-$pkgver.tar.xz" "$archive"
    checksum sha256 7ec9d18fb283d1f84a3a3eff3b7a72b09a10c9c006597b3fbabbb5958420a87d "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" -Dgir=false -Dvapi=false -Dgtk_doc=false -Dinstall_tests=false
    target_meson_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libgtksourceview-4.so.0*'
    keep+=(/usr/share/gtksourceview-4/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
