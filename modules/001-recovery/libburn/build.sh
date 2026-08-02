#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libburn
pkgver=1.5.6
depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/libburn-$pkgver.tar.gz"
    download "https://files.libburnia-project.org/releases/libburn-$pkgver.tar.gz" "$archive"
    checksum sha256 7295491b4be5eeac5e7a3fb2067e236e2955ffdc6bbd45f546466edee321644b "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/c23-signal-handler.patch" "$srcdir/c23-signal-handler.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/c23-signal-handler.patch"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --enable-shared
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(/usr/bin/cdrskin)
    package_add_library_family keep 'libburn.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
