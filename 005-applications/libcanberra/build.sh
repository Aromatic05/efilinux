#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libcanberra
pkgver=0.30
depends=(glib glibc gtk3)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libcanberra-$pkgver.tar.xz"
    download "https://0pointer.de/lennart/projects/libcanberra/libcanberra-$pkgver.tar.xz" "$archive"
    checksum sha256 c2b671e67e0c288a69fc33dc1b6f1b534d07882c2aceed37004bf48c601afa72 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --disable-alsa --disable-oss --disable-gstreamer --disable-gtk-doc
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libcanberra.so.0*'
    package_add_library_family keep 'libcanberra-gtk3.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
