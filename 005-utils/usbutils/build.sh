#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=usbutils
pkgver=019
depends=(glibc libusb udev)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)
prepare() {
    local archive="$downloaddir/usbutils-$pkgver.tar.xz"
    download "https://www.kernel.org/pub/linux/utils/usb/usbutils/usbutils-$pkgver.tar.xz" "$archive"
    checksum sha256 659f40c440e31ba865c52c818a33d3ba6a97349e3353f8b1985179cb2aa71ec5 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir"
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/lsusb /usr/bin/usbhid-dump /usr/bin/usb-devices; }
recipe_main "$@"
