#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libusb
pkgver=1.0.29
depends=(glibc udev)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/libusb-$pkgver.tar.bz2"
    download "https://github.com/libusb/libusb/releases/download/v$pkgver/libusb-$pkgver.tar.bz2" "$archive"
    checksum sha256 5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --enable-udev \
        --disable-log \
        --disable-examples-build \
        --disable-tests-build
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libusb-1.0.so.0*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
