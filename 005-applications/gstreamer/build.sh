#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=gstreamer
pkgver=1.28.5
depends=(glib glibc)
builddepends=()
makedepends=(bison flex gcc meson ninja pkg-config python3)
prepare() {
    local archive="$downloaddir/gstreamer-$pkgver.tar.xz"
    download "https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-$pkgver.tar.xz" "$archive"
    checksum sha256 a5a9f783809b17a8eb774f4a7695b2cb8cba6b15520129906f87eaf30e7f8469 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --auto-features=disabled \
        -Dgst_debug=false \
        -Dgst_parse=true \
        -Dregistry=true \
        -Dtracer_hooks=false \
        -Dptp-helper=disabled \
        -Doption-parsing=true \
        -Dcheck=disabled \
        -Dlibunwind=disabled \
        -Dlibdw=disabled \
        -Dbash-completion=disabled \
        -Dcoretracers=disabled \
        -Dexamples=disabled \
        -Dtests=disabled \
        -Dbenchmarks=disabled \
        -Dtools=enabled \
        -Dintrospection=disabled \
        -Dnls=disabled \
        -Dextra-checks=disabled \
        -Ddoc=disabled \
        -Dpackage-name='EFI Linux GStreamer'
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/libexec"; }
package() {
    local -a keep=(
        /usr/bin/gst-inspect-1.0
        /usr/bin/gst-launch-1.0
        /usr/lib/gstreamer-1.0/
        /usr/libexec/gstreamer-1.0/gst-plugin-scanner
    )
    package_add_library_family keep 'libgstreamer-1.0.so.0*'
    package_add_library_family keep 'libgstbase-1.0.so.0*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
