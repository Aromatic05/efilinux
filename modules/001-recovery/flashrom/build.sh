#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=flashrom
pkgver=1.7.0
depends=(glibc libusb pciutils)
builddepends=()
makedepends=(cmake gcc meson ninja pkg-config python3)
prepare() {
    local archive="$downloaddir/flashrom-v$pkgver.tar.xz"
    download "https://download.flashrom.org/releases/flashrom-v$pkgver.tar.xz" "$archive"
    checksum sha256 4328ace9833f7efe7c334bdd73482cde8286819826cc00149e83fba96bf3ab4f "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --sbindir=bin \
        -Dtests=disabled \
        -Ddocumentation=disabled \
        -Dman-pages=disabled \
        -Dbash_completion=disabled \
        -Duse_git_version=disabled \
        -Dprogrammer=group_internal,group_external,dummy
    target_meson_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(/usr/bin/flashrom)
    package_add_library_family keep 'libflashrom.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
