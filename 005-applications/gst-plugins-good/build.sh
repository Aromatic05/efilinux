#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=gst-plugins-good
pkgver=1.28.5
depends=(gdk-pixbuf glib glibc gst-plugins-base gstreamer libjpeg-turbo libpng pulseaudio)
builddepends=()
makedepends=(gcc meson nasm ninja pkg-config python3)
prepare() {
    local archive="$downloaddir/gst-plugins-good-$pkgver.tar.xz"
    download "https://gstreamer.freedesktop.org/src/gst-plugins-good/gst-plugins-good-$pkgver.tar.xz" "$archive"
    checksum sha256 58b45d24a1d77b39d7bb7d9ccc6e2d76bbf28618998c335c163f18e6f94a9324 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --auto-features=disabled \
        -Daudioparsers=enabled \
        -Dautodetect=enabled \
        -Davi=enabled \
        -Ddeinterlace=enabled \
        -Dflv=enabled \
        -Did3demux=enabled \
        -Dimagefreeze=enabled \
        -Disomp4=enabled \
        -Dmatroska=enabled \
        -Dreplaygain=enabled \
        -Dvideocrop=enabled \
        -Dwavparse=enabled \
        -Dgdk-pixbuf=enabled \
        -Djpeg=enabled \
        -Dpng=enabled \
        -Dpulse=enabled \
        -Dadaptivedemux2=disabled \
        -Dgtk3=disabled \
        -Dsoup=disabled \
        -Dv4l2=disabled \
        -Dximagesrc=disabled \
        -Dexamples=disabled \
        -Dtests=disabled \
        -Dnls=disabled \
        -Dorc=disabled \
        -Dorc-compiler=disabled \
        -Dasm=enabled \
        -Ddoc=disabled \
        -Dpackage-name='EFI Linux GStreamer Good'
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() { package_keep /usr/lib/gstreamer-1.0/; }
recipe_main "$@"
