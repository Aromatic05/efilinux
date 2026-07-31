#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=epdfview
pkgver=20200814

depends=(gcc-libs glib glibc gtk3 poppler)
builddepends=()
makedepends=(gcc gettext meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/epdfview-gtk3-$pkgver.tar.xz"

    download "https://anduin.linuxfromscratch.org/BLFS/epdfview-gtk3/epdfview-gtk3-$pkgver.tar.xz" "$archive"
    checksum sha256 fa74404ecce72517d01f5c1a6a2cffa4461eb3c38c1712ae228b3fd3520ca73e "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Denable-printing=false \
        -Dbuild-tests=false \
        -Dbuild-docs=false \
        -Dinstall-docs=false \
        -Denable-nls=true
    target_meson_install "$builddir" "$develdir"
}

devel() {
    prune_translations "$develdir"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/epdfview \
        /usr/share/applications/epdfview.desktop \
        /usr/share/epdfview/ \
        /usr/share/icons/hicolor/24x24/apps/epdfview.png \
        /usr/share/icons/hicolor/32x32/apps/epdfview.png \
        /usr/share/icons/hicolor/48x48/apps/epdfview.png \
        /usr/share/icons/hicolor/scalable/apps/epdfview.svg \
        /usr/share/locale/zh_CN/LC_MESSAGES/epdfview.mo
}

recipe_main "$@"
