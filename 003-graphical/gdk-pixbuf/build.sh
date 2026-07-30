#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=gdk-pixbuf
pkgver=2.44.7

depends=(glib glibc libjpeg-turbo libpng)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/gdk-pixbuf-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-2.44.7.tar.xz" "$archive"
    checksum sha256 172f80e3626ec31520a970400f1a3694e04718f6c2cd2885f75250fb5a6995a4 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Dpng=enabled \
        -Djpeg=enabled \
        -Dgif=enabled \
        -Dtiff=disabled \
        -Dglycin=disabled \
        -Dandroid=disabled \
        -Dothers=disabled \
        -Dbuiltin_loaders=png,jpeg,gif \
        -Ddocumentation=false \
        -Dintrospection=disabled \
        -Dman=false \
        -Dtests=false \
        -Dinstalled_tests=false \
        -Dgio_sniffing=false \
        -Dthumbnailer=disabled \
        -Dlegacy_xpm=disabled
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=(
        /usr/bin/gdk-pixbuf-query-loaders
        /usr/bin/gdk-pixbuf-csource
    )
    package_add_library_family keep 'libgdk_pixbuf-2.0.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
