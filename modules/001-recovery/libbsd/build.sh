#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libbsd
pkgver=0.12.2
depends=(glibc libmd)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/libbsd-$pkgver.tar.xz"
    download "https://libbsd.freedesktop.org/releases/libbsd-$pkgver.tar.xz" "$archive"
    checksum sha256 b88cc9163d0c652aaf39a99991d974ddba1c3a9711db8f1b5838af2a14731014 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/lib"
}
package() {
    local -a keep=()
    package_add_library_family keep 'libbsd.so.0*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
