#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=parole
pkgver=4.20.0
depends=(dbus dbus-glib gcc-libs glib glibc gst-libav gst-plugins-bad gst-plugins-base gst-plugins-good gstreamer gtk3 xfce xorg)
builddepends=()
makedepends=(gcc gettext meson ninja pkg-config)
prepare() {
    local archive="$downloaddir/parole-$pkgver.tar.xz"
    download "https://archive.xfce.org/src/apps/parole/4.20/parole-$pkgver.tar.xz" "$archive"
    checksum sha256 5cf753e670d6518701133eb860d8bceb3a08a496af6a2b7cc67b93320230c983 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dx11=enabled \
        -Dwayland=disabled \
        -Dtaglib=disabled \
        -Dnotify-plugin=disabled \
        -Dmpris2-plugin=enabled \
        -Dtray-plugin=disabled \
        -Dgtk-doc=false
    target_meson_install "$builddir" "$develdir"
}
devel() {
    prune_translations "$develdir"
    find "$develdir" -type f -name '*.la' -delete 2>/dev/null || true
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(
        /usr/bin/parole
        /usr/lib/parole-0/
        /usr/share/applications/org.xfce.Parole.desktop
        /usr/share/icons/hicolor/
        /usr/share/metainfo/parole.appdata.xml
        /usr/share/parole/
    )
    [[ ! -f "$pkgdir/usr/share/locale/zh_CN/LC_MESSAGES/parole.mo" ]] || \
        keep+=(/usr/share/locale/zh_CN/LC_MESSAGES/parole.mo)
    package_keep "${keep[@]}"
}
recipe_main "$@"
