#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
source "$ROOT/modules/001-recovery/lib/target-layout.sh"
pkgname=hardinfo2
pkgver=2.3.1
depends=(
    cairo dmidecode glib glibc gtk3 json-glib mesa-utils pciutils udisks usbutils
    util-linux xdg-utils xorg zlib
)
builddepends=()
makedepends=(cmake gcc msgfmt ninja patch pkg-config)
prepare() {
    local archive="$downloaddir/hardinfo2-$pkgver.tar.gz"
    download "https://github.com/hardinfo2/hardinfo2/archive/refs/tags/release-$pkgver.tar.gz" "$archive"
    checksum sha256 59b30378127dde8e0af92de1a23ebcee706820a862581a603543a99c357bcecb "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/hardinfo2-offline.patch" "$srcdir/hardinfo2-offline.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    input_shared_file "$ROOT/modules/001-recovery/lib/target-layout.sh" "$srcdir/recovery-target-layout.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/hardinfo2-offline.patch"
    grep -qx 'SET(CMAKE_INSTALL_PREFIX "/usr")' "$srcdir/source/CMakeLists.txt" ||
        die "Hardinfo2 install-prefix override changed upstream"
    sed -i '/^SET(CMAKE_INSTALL_PREFIX "\/usr")$/d' "$srcdir/source/CMakeLists.txt"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_INSTALL_PREFIX=/opt/recovery \
        -DHARDINFO2_GTK3=ON \
        -DHARDINFO2_LIBSOUP3=OFF \
        -DHARDINFO2_NOSSL=ON \
        -DHARDINFO2_QT5=OFF \
        -DHARDINFO2_QT6=OFF \
        -DHARDINFO2_SERVICE=OFF \
        -DHARDINFO2_VK=OFF \
        -DHARDINFO2_VK_WAYLAND=OFF \
        -DHARDINFO2_VK_X11=OFF
    target_cmake_install "$builddir" "$develdir"
    recovery_prune_translations "$develdir"
    rm -f "$develdir/opt/recovery/bin/hwinfo2_fetch_sysdata"
    sed -i \
        -e 's#^Exec=.*#Exec=/opt/recovery/bin/hardinfo2#' \
        -e 's#^Icon=.*#Icon=computer#' \
        -e 's#^Categories=.*#Categories=System;#' \
        "$develdir/opt/recovery/share/applications/hardinfo2.desktop"
    recovery_publish_usr_paths "$develdir" \
        share/applications
}
check() { [[ -x "$develdir/opt/recovery/bin/hardinfo2" ]] || die "Hardinfo2 binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/hardinfo2" "$develdir/opt/recovery/lib/hardinfo2/modules"; }
package() {
    package_keep \
        /opt/recovery/bin/hardinfo2 \
        /opt/recovery/lib/hardinfo2/ \
        /usr/share/applications/hardinfo2.desktop \
        /opt/recovery/share/hardinfo2/ \
        /opt/recovery/share/locale/
}
recipe_main "$@"
