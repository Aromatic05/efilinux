#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=thunar-archive-plugin
pkgver=0.5.2
depends=(glib glibc gtk3 xfce xarchiver)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/thunar-archive-plugin-$pkgver.tar.bz2"
    download "https://archive.xfce.org/src/thunar-plugins/thunar-archive-plugin/0.5/thunar-archive-plugin-$pkgver.tar.bz2" "$archive"
    checksum sha256 6379f877bcfc0ea85db9f43723b6fb317893050c712bd03c2ae3232fb9d5ade3 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-debug
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
    find "$develdir/usr/lib" -type f -name '*.la' -delete
}

package() {
    local -a keep=(/usr/lib/thunarx-3/ /usr/share/icons/hicolor/)
    [[ ! -d "$pkgdir/usr/share/Thunar" ]] || keep+=(/usr/share/Thunar/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
