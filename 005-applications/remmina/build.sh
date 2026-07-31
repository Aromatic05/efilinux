#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=remmina
pkgver=1.4.43
depends=(
    cairo curl freerdp glib glibc gtk3 json-glib libsecret libsodium libssh
    libvncserver openssl pcre2 spice-gtk vte xorg
)
builddepends=()
makedepends=(cmake gcc gettext ninja pkg-config)
prepare() {
    local archive="$downloaddir/remmina-$pkgver.tar.gz"
    download "https://gitlab.com/Remmina/Remmina/-/archive/v$pkgver/Remmina-v$pkgver.tar.gz" "$archive"
    checksum sha256 16533f8a806daff524649bb45ae51e51f61685da94846006018b3c279ebe7035 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_SKIP_RPATH=ON \
        -DWITH_AVAHI=OFF \
        -DWITH_GCRYPT=OFF \
        -DWITH_FREERDP3=ON \
        -DWITH_WWW=OFF \
        -DWITH_X2GO=OFF \
        -DWITH_GVNC=OFF \
        -DWITH_PYTHONLIBS=OFF \
        -DWITH_KF5WALLET=OFF \
        -DWITH_ST=OFF \
        -DWITH_XDMCP=OFF \
        -DWITH_NX=OFF \
        -DWITH_NEWS=OFF \
        -DWITH_STATS=OFF \
        -DWITH_TIP=OFF \
        -DWITH_CUPS=OFF \
        -DWITH_MANPAGES=OFF \
        -DWITH_ICON_CACHE=OFF \
        -DWITH_UPDATE_DESKTOP_DB=OFF \
        -DWITH_TRANSLATIONS=ON \
        -DHAVE_LIBAPPINDICATOR=OFF \
        -DWITH_SSE2=ON \
        -DWITH_IPP=OFF \
        -DTOGTK4=OFF
    target_cmake_install "$builddir" "$develdir"
}
devel() {
    prune_translations "$develdir"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(
        /usr/bin/remmina
        /usr/lib/remmina/plugins/remmina-plugin-rdp.so
        /usr/lib/remmina/plugins/remmina-plugin-vnc.so
        /usr/lib/remmina/plugins/remmina-plugin-spice.so
        /usr/lib/remmina/plugins/remmina-plugin-secret.so
        /usr/share/remmina/theme/Breeze.colors
        /usr/share/remmina/theme/Cobalt2.colors
        /usr/share/remmina/theme/Dracula.colors
        /usr/share/remmina/theme/MaterialDark.colors
        /usr/share/remmina/theme/OneHalfDark.colors
        /usr/share/remmina/theme/OneHalfLight.colors
        /usr/share/remmina/theme/nord.colors
        /usr/share/remmina/theme/tokyonight.colors
        /usr/share/applications/
        /usr/share/icons/hicolor/
        /usr/share/metainfo/
        /usr/share/mime/packages/
    )
    local optional
    for optional in \
        /usr/share/glib-2.0/schemas/org.remmina.Remmina.gschema.xml \
        /usr/share/locale/zh_CN/LC_MESSAGES/remmina.mo; do
        [[ ! -e "$pkgdir$optional" ]] || keep+=("$optional")
    done
    package_keep "${keep[@]}"
}
recipe_main "$@"
