#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=pango
pkgver=1.58.0

depends=(cairo fontconfig freetype fribidi glib glibc harfbuzz xorg)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/pango-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/pango/1.58/pango-1.58.0.tar.xz" "$archive"
    checksum sha256 bc5bad6213ad4886a47d1e80292fd850b64159b50db67917a43d9ea80ee2298a "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Ddocumentation=false \
        -Dman-pages=false \
        -Dintrospection=disabled \
        -Dbuild-testsuite=false \
        -Dbuild-examples=false \
        -Dfontconfig=enabled \
        -Dsysprof=disabled \
        -Dlibthai=disabled \
        -Dcairo=enabled \
        -Dxft=enabled \
        -Dfreetype=enabled
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local family
    local -a keep=()

    for family in \
        'libpango-1.0.so.0*' \
        'libpangocairo-1.0.so.0*' \
        'libpangoft2-1.0.so.0*'; do
        package_add_library_family keep "$family"
    done
    package_keep "${keep[@]}"
}

recipe_main "$@"
