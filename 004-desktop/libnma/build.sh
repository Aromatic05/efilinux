#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libnma
pkgver=1.10.6

depends=(glib glibc gtk3 networkmanager)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libnma-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/libnma/1.10/libnma-$pkgver.tar.xz" "$archive"
    checksum sha256 53a6fb2b190ad37c5986caed3e98bede7c3c602399ee4f93c8fc054303d76dab "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dlibnma_gtk4=false \
        -Dgcr=false \
        -Diso_codes=false \
        -Dmobile_broadband_provider_info=false \
        -Dgtk_doc=false \
        -Dintrospection=false \
        -Dvapi=false \
        -Dmore_asserts=0
    target_meson_install "$builddir" "$develdir"
}

devel() {
    prune_translations "$develdir"
    strip_all "$develdir/usr/lib"
}

package() {
    rm -rf \
        "$pkgdir/usr/include" \
        "$pkgdir/usr/lib/pkgconfig" \
        "$pkgdir/usr/share/gir-1.0" \
        "$pkgdir/usr/share/gtk-doc"
    find "$pkgdir/usr/lib" -type f \
        \( -name '*.a' -o -name '*.la' -o -name '*.pc' \) -delete 2>/dev/null || true
    find "$pkgdir/usr/lib" -maxdepth 1 -type l -name 'lib*.so' -delete
    rm -f "$pkgdir/usr/share/glib-2.0/schemas/org.gnome.nm-applet.gschema.xml"
}

recipe_main "$@"
