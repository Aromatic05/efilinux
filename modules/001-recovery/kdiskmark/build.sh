#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
source "$ROOT/modules/001-recovery/lib/target-layout.sh"
pkgname=kdiskmark
pkgver=3.3.0
_singleapplication_commit=f1e15081dc57a9c03f7f4f165677f18802e1437a
depends=(dbus fio gcc-libs glibc qt6-base)
builddepends=(extra-cmake-modules)
makedepends=(cmake g++ ninja patch pkg-config qmake6)
prepare() {
    local archive="$downloaddir/kdiskmark-$pkgver.tar.gz"
    local single_archive="$downloaddir/singleapplication-$_singleapplication_commit.tar.gz"
    download "https://github.com/JonMagon/KDiskMark/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 f0c5d695d3566b36ef86eda1286edc5b4cb1c3d447ec5a4d36c6878e79cea113 "$archive"
    extract "$archive" "$srcdir/source"
    download \
        "https://github.com/itay-grudev/SingleApplication/archive/$_singleapplication_commit.tar.gz" \
        "$single_archive"
    checksum sha256 ddab4bec60e4221580f8bb65ac200619bd2d1c9144a8ac7dccc0c78ea4667dc2 "$single_archive"
    rm -rf "$srcdir/source/src/singleapplication"
    extract "$single_archive" "$srcdir/source/src/singleapplication"
    input_file "$recipedir/files/kdiskmark-recovery.patch" "$srcdir/kdiskmark-recovery.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    input_shared_file "$ROOT/modules/001-recovery/lib/target-layout.sh" "$srcdir/recovery-target-layout.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/kdiskmark-recovery.patch"
    grep -Fqx '                     << QStringLiteral("--ioengine=libaio")' \
        "$srcdir/source/src/helper.cpp" ||
        die "KDiskMark fio engine selection changed upstream"
    sed -i \
        's/QStringLiteral("--ioengine=libaio")/QStringLiteral("--ioengine=sync")/' \
        "$srcdir/source/src/helper.cpp"

    grep -Fqx '#include "singleapplication.h"' "$srcdir/source/src/main.cpp" ||
        die "KDiskMark SingleApplication include changed upstream"
    grep -Fqx '    SingleApplication a(argc, argv);' "$srcdir/source/src/main.cpp" ||
        die "KDiskMark SingleApplication construction changed upstream"
    sed -i \
        -e '/^#include "singleapplication.h"$/d' \
        -e 's/^    SingleApplication a(argc, argv);$/    QApplication a(argc, argv);/' \
        "$srcdir/source/src/main.cpp"
}
build() {
    local qt_host_bins
    qt_host_bins=$(qmake6 -query QT_HOST_BINS)
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_INSTALL_PREFIX=/opt/recovery \
        -DUSE_QT5=OFF \
        -DQT_HOST_PATH="$EFILINUX_SYSROOT/usr" \
        -DQt6_DIR="$EFILINUX_SYSROOT/usr/lib/cmake/Qt6" \
        -DECM_DIR="$EFILINUX_SYSROOT/usr/share/ECM/cmake" \
        -DKDE_INSTALL_LIBEXECDIR=libexec \
        -DKDE_INSTALL_DBUSDIR=share/dbus-1
    target_cmake_install "$builddir" "$develdir"

    install -d -m0755 "$develdir/opt/recovery/share/kdiskmark/kdiskmark/translations"
    "$qt_host_bins/lrelease" "$srcdir/source/data/translations/kdiskmark_zh_CN.ts" \
        -qm "$develdir/opt/recovery/share/kdiskmark/kdiskmark/translations/kdiskmark_zh_CN.qm"

    rm -rf \
        "$develdir/opt/recovery/share/dbus-1" \
        "$develdir/opt/recovery/share/polkit-1"
    sed -i \
        -e 's#^Exec=.*#Exec=/opt/recovery/bin/recovery-kdiskmark#' \
        -e 's#^Icon=.*#Icon=drive-harddisk#' \
        "$develdir/opt/recovery/share/applications/kdiskmark.desktop"
    recovery_publish_usr_paths "$develdir" \
        share/applications
}
check() {
    [[ -x "$develdir/opt/recovery/bin/kdiskmark" ]] || die "KDiskMark binary is missing"
    [[ -x "$develdir/opt/recovery/libexec/kdiskmark_helper" ]] || die "KDiskMark helper is missing"
}
devel() { strip_all "$develdir/opt/recovery/bin/kdiskmark" "$develdir/opt/recovery/libexec/kdiskmark_helper"; }
package() {
    package_keep \
        /opt/recovery/bin/kdiskmark \
        /opt/recovery/libexec/kdiskmark_helper \
        /usr/share/applications/kdiskmark.desktop \
        /opt/recovery/share/kdiskmark/
}
recipe_main "$@"
