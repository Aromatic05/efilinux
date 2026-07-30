#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=gparted
pkgver=1.7.0
depends=(glib glibc gtkmm libxml2 parted polkit util-linux)
builddepends=()
makedepends=(gcc g++ make pkg-config)

prepare() {
    local archive="$downloaddir/gparted-$pkgver.tar.gz"
    download "https://downloads.sourceforge.net/gparted/gparted-$pkgver.tar.gz" "$archive"
    checksum sha256 84ae3b9973e443a2175f07aa0dc2aceeadb1501e0f8953cec83b0ec3347b7d52 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir"
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/libexec"; }

package() {
    local -a keep=(/usr/bin/gparted /usr/libexec/gpartedbin /usr/share/applications/ /usr/share/icons/hicolor/)
    [[ ! -d "$pkgdir/usr/libexec" ]] || keep+=(/usr/libexec/)
    [[ ! -d "$pkgdir/usr/share/glib-2.0/schemas" ]] || keep+=(/usr/share/glib-2.0/schemas/)
    keep+=(/usr/share/polkit-1/actions/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
