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
    dbus
    fmt
    gdk-pixbuf
    glib
    glibc
    iso-codes
    libuv
    libxkbcommon
    libxkbcommon-x11-runtime
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
        -DENABLE_DBUS=ON \
        -DXKEYBOARDCONFIG_XKBBASE=/usr/share/X11/xkb \
        -DENABLE_WAYLAND=OFF \
        -DENABLE_ENCHANT=OFF \
        -DENABLE_EMOJI=OFF \
        -DBUILD_SPELL_DICT=OFF \
        -DENABLE_LIBUUID=OFF \
        -DENABLE_XDGAUTOSTART=ON \
        -DENABLE_TESTING_ADDONS=OFF \
        -DENABLE_TEST=OFF \
        -DENABLE_DOC=OFF
    target_cmake_install "$builddir" "$develdir"
}

install_runtime_wrapper() {
    local command=$1
    cat > "$develdir/usr/bin/$command" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH=/opt/fcitx5/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export FCITX_ADDON_DIRS=/opt/fcitx5/lib/fcitx5
export FCITX_DATA_DIRS=/opt/fcitx5/share/fcitx5
export XKB_CONFIG_ROOT=/usr/share/X11/xkb
exec /opt/fcitx5/bin/$command "\$@"
EOF
    chmod 0755 "$develdir/usr/bin/$command"
}

devel() {
    local command opt_root="$develdir/opt/fcitx5"

    prune_translations "$develdir"
    find "$develdir/usr/lib/cmake" -type f -name '*.cmake' -exec \
        sed -i \
            -e 's#INTERFACE_INCLUDE_DIRECTORIES "/usr/include/Fcitx5#INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SYSROOT}/usr/include/Fcitx5#g' \
            -e 's#set(FCITX_INSTALL_LIBDATADIR ".*")#set(FCITX_INSTALL_LIBDATADIR "/usr/lib")#' \
            {} +
    sed -i 's/^Categories=System;Utility;$/Categories=Utility;/' \
        "$develdir/usr/share/applications/org.fcitx.Fcitx5.desktop" \
        "$develdir/etc/xdg/autostart/org.fcitx.Fcitx5.desktop"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/lib/fcitx5"

    install -d -m0755 "$opt_root/bin" "$opt_root/lib" "$opt_root/share"
    for command in fcitx5 fcitx5-diagnose fcitx5-remote; do
        [[ -f "$develdir/usr/bin/$command" ]] || continue
        cp -a "$develdir/usr/bin/$command" "$opt_root/bin/$command"
        install_runtime_wrapper "$command"
    done
    cp -a "$develdir/usr/lib/fcitx5" "$opt_root/lib/"
    find "$develdir/usr/lib" -maxdepth 1 \
        \( -type f -o -type l \) -name 'libFcitx5*.so*' \
        -exec cp -a -t "$opt_root/lib" {} +
    cp -a "$develdir/usr/share/fcitx5" "$opt_root/share/"

    # Keep the Xfce/GTK/XIM path and the StatusNotifier tray. Other desktop
    # frontends and optional utilities only add dead weight to this module.
    local addon
    for addon in fcitx4frontend ibusfrontend kimpanel notifications unicode virtualkeyboard; do
        rm -f \
            "$opt_root/lib/fcitx5/lib${addon}.so" \
            "$opt_root/share/fcitx5/addon/${addon}.conf"
    done
    rm -rf "$opt_root/share/fcitx5/unicode"
    if [[ -d "$opt_root/share/fcitx5/default" ]]; then
        find "$opt_root/share/fcitx5/default" -maxdepth 1 -type f \
            ! -name en_US ! -name zh_CN -delete
    fi

    if [[ -f "$develdir/etc/xdg/autostart/org.fcitx.Fcitx5.desktop" ]]; then
        install -d -m0755 "$opt_root/etc/xdg/autostart"
        install -m0644 "$develdir/etc/xdg/autostart/org.fcitx.Fcitx5.desktop" \
            "$opt_root/etc/xdg/autostart/org.fcitx.Fcitx5.desktop"
    fi
}

package() {
    package_keep \
        /opt/fcitx5/ \
        /usr/bin/fcitx5 \
        /usr/bin/fcitx5-diagnose \
        /usr/bin/fcitx5-remote \
        /usr/share/applications/fcitx5-configtool.desktop \
        /usr/share/applications/org.fcitx.Fcitx5.desktop \
        /usr/share/icons/hicolor/
}

recipe_main "$@"
