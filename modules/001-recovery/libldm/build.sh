#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libldm
pkgver=0.2.5
depends=(device-mapper glib glibc json-glib readline util-linux zlib)
builddepends=()
makedepends=(autoconf automake gcc libtool make pkg-config)
prepare() {
    local archive="$downloaddir/libldm-$pkgver.tar.gz"
    download "https://github.com/mdbooth/libldm/archive/refs/tags/libldm-$pkgver.tar.gz" "$archive"
    checksum sha256 61bb2f2367b1df59f818cb96794d1770a0def956bd2c343dccf1425dae3021b5 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/c23-prototypes.patch" "$srcdir/c23-prototypes.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/c23-prototypes.patch"
}
build() {
    target_autotools_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --disable-gtk-doc \
        --disable-introspection
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin/ldmtool" "$develdir/usr/lib"
}
package() {
    local -a keep=(/usr/bin/ldmtool)
    package_add_library_family keep 'libldm-1.0.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
