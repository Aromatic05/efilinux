#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=gtk3
pkgver=3.24.52

depends=(
    at-spi2-core cairo desktop-file-utils fontconfig gdk-pixbuf glib glibc
    hicolor-icon-theme libepoxy pango shared-mime-info xorg
)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/gtk-$pkgver.tar.gz"
    download "https://gitlab.gnome.org/GNOME/gtk/-/archive/3.24.52/gtk-3.24.52.tar.gz" "$archive"
    checksum sha256 e62514019679f831fcb37f3d294a761c3a6c14f1d346745ad11d70c2be17146e "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Dx11_backend=true \
        -Dwayland_backend=false \
        -Dbroadway_backend=false \
        -Dwin32_backend=false \
        -Dquartz_backend=false \
        -Dxinerama=yes \
        -Dcloudproviders=false \
        -Dprofiler=false \
        -Dtracker3=false \
        -Dprint_backends=file \
        -Dcolord=no \
        -Dgtk_doc=false \
        -Dman=false \
        -Dintrospection=false \
        -Ddemos=false \
        -Dexamples=false \
        -Dtests=false \
        -Dinstalled_tests=false \
        -Dbuiltin_immodules=xim
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=(
        /usr/bin/gtk-update-icon-cache
        /usr/share/gtk-3.0/
        /usr/share/themes/
        /usr/share/glib-2.0/schemas/
    )
    package_add_library_family keep 'libgtk-3.so.0*'
    package_add_library_family keep 'libgdk-3.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
