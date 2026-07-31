#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=galculator
pkgver=2.1.4
depends=(glib glibc gtk3)
builddepends=()
makedepends=(autoreconf automake autopoint flex gcc intltool-extract intltool-merge intltool-update libtool make msgfmt patch pkg-config)

prepare() {
    local archive="$downloaddir/galculator-v$pkgver.tar.gz"
    download "https://github.com/ib/galculator/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 dcbdb48ddf8a3f68b9aa5902f880f174fd269de2b7410988148d05871012e142 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/patches/0001-fix-duplicate-preferences-definition.patch" \
        "$srcdir/fix-duplicate-preferences-definition.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    patch -d "$srcdir/source" -Np1 < "$srcdir/fix-duplicate-preferences-definition.patch"
    CFLAGS="$CFLAGS -std=gnu17"
    target_autotools_configure "$srcdir/source" "$builddir" --enable-gtk3 --disable-quadmath
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin"; }

package() {
    local -a keep=(
        /usr/bin/galculator
        /usr/share/applications/galculator.desktop
        /usr/share/galculator/ui/about.ui
        /usr/share/galculator/ui/basic_buttons_gtk3.ui
        /usr/share/galculator/ui/classic_view.ui
        /usr/share/galculator/ui/dispctrl_bottom_gtk3.ui
        /usr/share/galculator/ui/dispctrl_right_gtk3.ui
        /usr/share/galculator/ui/dispctrl_right_vertical_gtk3.ui
        /usr/share/galculator/ui/main_frame.ui
        /usr/share/galculator/ui/paper_view.ui
        /usr/share/galculator/ui/prefs_gtk3.ui
        /usr/share/galculator/ui/scientific_buttons_gtk3.ui
    )
    [[ ! -d "$pkgdir/usr/share/icons/hicolor" ]] || keep+=(/usr/share/icons/hicolor/)
    [[ ! -d "$pkgdir/usr/share/pixmaps" ]] || keep+=(/usr/share/pixmaps/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
