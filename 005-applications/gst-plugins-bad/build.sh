#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=gst-plugins-bad
pkgver=1.28.5
depends=(glib glibc gst-plugins-base gstreamer)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)
prepare() {
    local archive="$downloaddir/gst-plugins-bad-$pkgver.tar.xz"
    download "https://gstreamer.freedesktop.org/src/gst-plugins-bad/gst-plugins-bad-$pkgver.tar.xz" "$archive"
    checksum sha256 d8af55faef2958c1a8663751475ee46f5164877cf4d8c5913ea906ef180aeb71 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --auto-features=disabled \
        -Dvideoparsers=enabled \
        -Dexamples=disabled \
        -Dtests=disabled \
        -Dtools=disabled \
        -Dintrospection=disabled \
        -Dnls=disabled \
        -Dorc=disabled \
        -Dorc-compiler=disabled \
        -Ddoc=disabled \
        -Dpackage-name='EFI Linux GStreamer Video Parsers'
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=(/usr/lib/gstreamer-1.0/libgstvideoparsersbad.so)
    package_add_library_family keep 'libgstcodecparsers-1.0.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
