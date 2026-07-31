#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=gst-libav
pkgver=1.28.5
depends=(ffmpeg-libs glib glibc gst-plugins-base gstreamer)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)
prepare() {
    local archive="$downloaddir/gst-libav-$pkgver.tar.xz"
    download "https://gstreamer.freedesktop.org/src/gst-libav/gst-libav-$pkgver.tar.xz" "$archive"
    checksum sha256 452854656056f0b16511a1d9ad4f2679ff5e5a87c89f90cf7ee5dec005ddb1e4 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --auto-features=disabled \
        -Dtests=disabled \
        -Ddoc=disabled \
        -Dpackage-name='EFI Linux GStreamer Libav'
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() { package_keep /usr/lib/gstreamer-1.0/libgstlibav.so; }
recipe_main "$@"
