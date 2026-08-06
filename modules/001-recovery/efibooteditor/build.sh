#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=efibooteditor
pkgver=1.5.7
depends=(efivar gcc-libs glibc qt6-base zlib)
builddepends=()
makedepends=(cmake g++ ninja patch pkg-config qmake6)
prepare() {
    local archive="$downloaddir/efibooteditor-$pkgver.tar.gz"
    download "https://github.com/Neverous/efibooteditor/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 25f79860c6eb6dcc66bdd1139db22611f157783c04c98b16e51a70d3a55252e2 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/efibooteditor-recovery.patch" "$srcdir/efibooteditor-recovery.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/efibooteditor-recovery.patch"
}
build() {
    local qt_host_bins
    qt_host_bins=$(qmake6 -query QT_HOST_BINS)
    export BUILD_VERSION="v$pkgver"
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_INSTALL_PREFIX=/opt/recovery \
        -DQT_VERSION_MAJOR=6 \
        -DQt6_DIR="$EFILINUX_SYSROOT/usr/lib/cmake/Qt6" \
        -DQT_HOST_PATH="$EFILINUX_SYSROOT/usr"
    target_cmake_install "$builddir" "$develdir"

    rm -f \
        "$develdir/opt/recovery/bin/run-efibooteditor" \
        "$develdir/opt/recovery/share/applications/EFIBootEditor.desktop" \
        "$develdir/opt/recovery/share/metainfo/EFIBootEditor.metainfo.xml" \
        "$develdir/opt/recovery/share/polkit-1/actions/org.x.efibooteditor.policy"

    install -d -m0755 "$develdir/opt/recovery/share/efibooteditor/translations"
    "$qt_host_bins/lrelease" "$srcdir/source/translations/efibooteditor_zh_Hans.ts" \
        -qm "$develdir/opt/recovery/share/efibooteditor/translations/efibooteditor_zh_CN.qm"
}
check() { [[ -x "$develdir/opt/recovery/bin/efibooteditor" ]] || die "EFI Boot Editor binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/efibooteditor"; }
package() {
    package_keep \
        /opt/recovery/bin/efibooteditor \
        /opt/recovery/share/efibooteditor/
}
recipe_main "$@"
