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
    target_release_configure "$srcdir/source" "$builddir" --disable-doc
    target_make_install "$builddir" "$develdir"
    sed -i 's/^[[:space:]]*egrep /	grep -E /' "$develdir/usr/bin/gparted"
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/libexec"; }

package() {
    local -a keep=(
        /usr/bin/gparted
        /usr/libexec/gpartedbin
        /usr/share/applications/gparted.desktop
        /usr/share/icons/hicolor/
        /usr/share/locale/zh_CN/LC_MESSAGES/gparted.mo
        /usr/share/polkit-1/actions/org.gnome.gparted.policy
    )
    package_keep "${keep[@]}"
}

recipe_main "$@"
