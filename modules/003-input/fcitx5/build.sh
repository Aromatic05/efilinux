#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=fcitx5
pkgver=5.1.12
depends=(
    cairo
    fmt
    gdk-pixbuf
    glib
    glibc
    iso-codes
    libuv
    libxkbcommon
    pango
    xcb-imdkit
    xcb-util-keysyms
    xcb-util-wm
    xkeyboard-config
    xorg
    zlib
)
builddepends=(extra-cmake-modules fmt libuv xcb-imdkit xcb-util-keysyms xcb-util-wm)
makedepends=(cmake gcc g++ gettext ninja pkg-config)

prepare() {
    local archive="$downloaddir/fcitx5-$pkgver.tar.gz"
    download "https://github.com/fcitx/fcitx5/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 04fabc12cb8702f06aeb1399f30d41dd9c17a997ccac9a53352ba21a8aef16e7 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/event-loop-include.patch" \
        "$srcdir/event-loop-include.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/event-loop-include.patch"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DEVENT_LOOP_BACKEND=libuv \
        -DUSE_SYSTEMD=OFF \
        -DENABLE_DBUS=OFF \
        -DENABLE_WAYLAND=OFF \
        -DENABLE_ENCHANT=OFF \
        -DENABLE_EMOJI=OFF \
        -DBUILD_SPELL_DICT=OFF \
        -DENABLE_LIBUUID=OFF \
        -DENABLE_XDGAUTOSTART=OFF \
        -DENABLE_TESTING_ADDONS=OFF \
        -DENABLE_TEST=OFF \
        -DENABLE_DOC=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    prune_translations "$develdir"
    find "$develdir/usr/lib/cmake" -type f -name '*.cmake' -exec \
        sed -i \
            -e 's#INTERFACE_INCLUDE_DIRECTORIES "/usr/include/Fcitx5#INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SYSROOT}/usr/include/Fcitx5#g' \
            -e 's#set(FCITX_INSTALL_LIBDATADIR ".*")#set(FCITX_INSTALL_LIBDATADIR "/usr/lib")#' \
            {} +
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/lib/fcitx5"
}

package() {
    local -a keep=(/usr/bin/fcitx5 /usr/lib/fcitx5/ /usr/share/fcitx5/)
    package_add_library_family keep 'libFcitx5Core.so.7*'
    package_add_library_family keep 'libFcitx5Config.so.6*'
    package_add_library_family keep 'libFcitx5Utils.so.2*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
