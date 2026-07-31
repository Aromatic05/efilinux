#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=gst-plugins-base
pkgver=1.28.5
depends=(alsa-lib glib glibc gstreamer pango xorg)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)
prepare() {
    local archive="$downloaddir/gst-plugins-base-$pkgver.tar.xz"
    download "https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-$pkgver.tar.xz" "$archive"
    checksum sha256 776f19228f91fd25bbf54d9850597e158507f594872a52b9b6814e2429b43eaa "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --auto-features=disabled \
        -Dadder=disabled \
        -Dapp=disabled \
        -Daudioconvert=enabled \
        -Daudiomixer=disabled \
        -Daudiorate=enabled \
        -Daudioresample=enabled \
        -Daudiotestsrc=disabled \
        -Dcompositor=disabled \
        -Ddebugutils=disabled \
        -Ddrm=disabled \
        -Dencoding=disabled \
        -Dgio=enabled \
        -Dgio-typefinder=enabled \
        -Doverlaycomposition=enabled \
        -Dpbtypes=enabled \
        -Dplayback=enabled \
        -Drawparse=enabled \
        -Dsubparse=enabled \
        -Dtcp=disabled \
        -Dtypefind=enabled \
        -Dvideoconvertscale=enabled \
        -Dvideorate=enabled \
        -Dvideotestsrc=disabled \
        -Dvolume=enabled \
        -Dalsa=enabled \
        -Dpango=enabled \
        -Dx11=enabled \
        -Dxshm=enabled \
        -Dxvideo=disabled \
        -Dxi=disabled \
        -Dgl=disabled \
        -Dexamples=disabled \
        -Dtests=disabled \
        -Dtools=disabled \
        -Dintrospection=disabled \
        -Dnls=disabled \
        -Dorc=disabled \
        -Dorc-compiler=disabled \
        -Ddoc=disabled \
        -Dpackage-name='EFI Linux GStreamer Base'
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=(/usr/lib/gstreamer-1.0/)
    local library

    for library in allocators audio pbutils riff rtp tag video; do
        package_add_library_family keep "libgst$library-1.0.so.0*"
    done
    package_keep "${keep[@]}"
}
recipe_main "$@"
