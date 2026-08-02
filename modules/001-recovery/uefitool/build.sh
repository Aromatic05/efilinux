#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=uefitool
pkgver=A75
depends=(gcc-libs glibc qt6-base)
builddepends=()
makedepends=(cmake gcc g++ ninja)
prepare() {
    local archive="$downloaddir/UEFITool-$pkgver.tar.gz"
    download "https://github.com/LongSoft/UEFITool/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 f624ac80cdd716ed5e071d46f1516c84ce99b44fd5ce72663903c0a569c40770 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_TESTING=OFF \
        -DQt6_DIR="$EFILINUX_SYSROOT/usr/lib/cmake/Qt6" \
        -DQT_HOST_PATH="$EFILINUX_SYSROOT/usr"
    cmake --build "$builddir" -j "$EFILINUX_JOBS"
    install -d -m0755 "$develdir/usr/bin" "$develdir/usr/share/applications"
    install -m0755 "$builddir/UEFITool/uefitool" "$develdir/usr/bin/UEFITool"
    install -m0755 "$builddir/UEFIExtract/uefiextract" "$develdir/usr/bin/UEFIExtract"
    install -m0755 "$builddir/UEFIFind/uefifind" "$develdir/usr/bin/UEFIFind"
    install -m0644 "$srcdir/source/UEFITool/uefitool.desktop" \
        "$develdir/usr/share/applications/uefitool.desktop"
    sed -i \
        -e 's|^Exec=.*|Exec=/opt/recovery/bin/UEFITool %f|' \
        -e 's|^Categories=.*|Categories=System;|' \
        "$develdir/usr/share/applications/uefitool.desktop"
    for size in 16 32 64 128 256 512; do
        install -d -m0755 "$develdir/usr/share/icons/hicolor/${size}x${size}/apps"
        install -m0644 "$srcdir/source/UEFITool/icons/uefitool_${size}x${size}.png" \
            "$develdir/usr/share/icons/hicolor/${size}x${size}/apps/uefitool.png"
    done
}
check() {
    local command
    for command in UEFITool UEFIExtract UEFIFind; do
        [[ -x "$develdir/usr/bin/$command" ]] || die "$command was not built"
    done
}
devel() { strip_all "$develdir/usr/bin"; }
package() {
    package_keep \
        /usr/bin/UEFITool \
        /usr/bin/UEFIExtract \
        /usr/bin/UEFIFind \
        /usr/share/applications/uefitool.desktop \
        /usr/share/icons/hicolor/
}
recipe_main "$@"
