#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=gtkmm
pkgver=3.24.9
depends=(atkmm cairomm gdk-pixbuf glibc glibmm gtk3 libsigcxx pangomm xorg)
builddepends=()
makedepends=(gcc g++ meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/gtkmm-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/gtkmm/3.24/gtkmm-$pkgver.tar.xz" "$archive"
    checksum sha256 30d5bfe404571ce566a8e938c8bac17576420eb508f1e257837da63f14ad44ce "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" -Dbuild-documentation=false -Dbuild-demos=false -Dbuild-tests=false
    target_meson_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libgtkmm-3.0.so.1*'
    package_add_library_family keep 'libgdkmm-3.0.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
