#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=network-manager-applet
pkgver=1.36.0
sysroot=false

depends=(glib glibc gtk3 libnma libnotify libsecret networkmanager)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/network-manager-applet-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/network-manager-applet/1.36/network-manager-applet-$pkgver.tar.xz" "$archive"
    checksum sha256 a84704487ea3afe1485c47fb2ab598b8f779f540ae0dcbf0a1c5f85e64a7e253 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dappindicator=no \
        -Dwwan=false \
        -Dselinux=false \
        -Dteam=false \
        -Dmore_asserts=0
    target_meson_install "$builddir" "$develdir"
}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    rm -rf \
        "$pkgdir/usr/include" \
        "$pkgdir/usr/lib/pkgconfig" \
        "$pkgdir/usr/share/gir-1.0" \
        "$pkgdir/usr/share/gtk-doc" \
        "$pkgdir/usr/share/man" \
        "$pkgdir/usr/share/metainfo"
    find "$pkgdir/usr/lib" -type f \
        \( -name '*.a' -o -name '*.la' -o -name '*.pc' \) -delete 2>/dev/null || true
}

recipe_main "$@"
