#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=qt6-base
pkgver=6.10.2
depends=(
    dbus
    fontconfig
    freetype
    gcc-libs
    glibc
    libjpeg-turbo
    libpng
    libxkbcommon
    libxkbcommon-x11
    pcre2
    xcb-util-cursor
    xcb-util-image
    xcb-util-keysyms
    xcb-util-renderutil
    xcb-util-wm
    xorg
    zlib
)
builddepends=()
makedepends=(cmake gcc g++ ninja perl pkg-config python3)
prepare() {
    local archive="$downloaddir/qtbase-everywhere-src-$pkgver.tar.xz"
    download \
        "https://download.qt.io/official_releases/qt/6.10/6.10.2/submodules/qtbase-everywhere-src-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 aeb78d29291a2b5fd53cb55950f8f5065b4978c25fb1d77f627d695ab9adf21e "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    local cc cxx
    cc=$(target_compiler_wrapper gcc)
    cxx=$(target_compiler_wrapper g++)
    mkdir -p "$builddir"
    (
        cd "$builddir"
        PKG_CONFIG_PATH= \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/source/configure" \
            -prefix /usr \
            -bindir /usr/bin \
            -libdir /usr/lib \
            -libexecdir /usr/lib/qt6 \
            -plugindir /usr/lib/qt6/plugins \
            -release \
            -opensource \
            -confirm-license \
            -shared \
            -nomake examples \
            -nomake tests \
            -gui \
            -widgets \
            -dbus-linked \
            -no-icu \
            -no-opengl \
            -no-openssl \
            -fontconfig \
            -system-freetype \
            -system-libpng \
            -system-libjpeg \
            -xcb \
            -bundled-xcb-xinput \
            -qpa xcb \
            -default-qpa xcb \
            -- \
            -DCMAKE_C_COMPILER="$cc" \
            -DCMAKE_CXX_COMPILER="$cxx" \
            -DCMAKE_SYSROOT="$EFILINUX_SYSROOT" \
            -DCMAKE_C_FLAGS="$CFLAGS" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
            -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
            -DCMAKE_FIND_ROOT_PATH="$EFILINUX_SYSROOT" \
            -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
            -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
            -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
            -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
            -DFEATURE_accessibility=OFF \
            -DFEATURE_network=ON \
            -DFEATURE_printdialog=OFF \
            -DFEATURE_printer=OFF \
            -DFEATURE_sessionmanager=OFF \
            -DFEATURE_sql=OFF \
            -DFEATURE_vulkan=OFF
    )
    cmake --build "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" cmake --install "$builddir"
    target_normalize_pkg_config "$develdir"
}
check() {
    [[ -f "$develdir/usr/lib/libQt6Core.so.6" ]] || die "Qt6 Core runtime is missing"
    [[ -f "$develdir/usr/lib/libQt6DBus.so.6" ]] || die "Qt6 DBus runtime is missing"
    [[ -f "$develdir/usr/lib/libQt6Gui.so.6" ]] || die "Qt6 GUI runtime is missing"
    [[ -f "$develdir/usr/lib/libQt6Network.so.6" ]] || die "Qt6 Network runtime is missing"
    [[ -f "$develdir/usr/lib/libQt6Widgets.so.6" ]] || die "Qt6 Widgets runtime is missing"
    [[ -f "$develdir/usr/lib/libQt6XcbQpa.so.6" ]] || die "Qt6 XCB support library is missing"
    [[ -f "$develdir/usr/lib/qt6/plugins/platforms/libqxcb.so" ]] || \
        die "Qt6 XCB platform plugin is missing"
    [[ -f "$develdir/usr/lib/qt6/plugins/platforms/libqoffscreen.so" ]] || \
        die "Qt6 offscreen platform plugin is missing"
}
devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(
        /usr/lib/qt6/plugins/platforms/libqoffscreen.so
        /usr/lib/qt6/plugins/platforms/libqxcb.so
    )
    package_add_library_family keep 'libQt6Core.so.6*'
    package_add_library_family keep 'libQt6DBus.so.6*'
    package_add_library_family keep 'libQt6Gui.so.6*'
    package_add_library_family keep 'libQt6Network.so.6*'
    package_add_library_family keep 'libQt6Widgets.so.6*'
    package_add_library_family keep 'libQt6XcbQpa.so.6*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
