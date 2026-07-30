#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/003-graphical/desktop-support/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/004-desktop/extras/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command cmake curl find gcc g++ make meson ninja pkg-config sha256sum tar
ensure_directories

require_command intltool-extract intltool-merge intltool-update

recipe_inputs=(
    "$ROOT/002-system/desktop-config.sh"
    "$ROOT/003-graphical/config.sh"
    "$ROOT/003-graphical/desktop-support/config.sh"
    "$ROOT/004-desktop/config.sh"
    "$ROOT/004-desktop/extras/config.sh"
    "$ROOT/004-desktop/extras/build.sh"
)

restore_package() {
    binary_package_restore_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

publish_package() {
    binary_package_publish_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

prune_translations() {
    local staging=$1
    local locale_directory="$staging/usr/share/locale"
    local entry

    [[ -d "$locale_directory" ]] || return 0
    while IFS= read -r -d '' entry; do
        case $(basename -- "$entry") in
            en|en_US|zh_CN|zh_Hans) ;;
            *) rm -rf -- "$entry" ;;
        esac
    done < <(find "$locale_directory" -mindepth 1 -maxdepth 1 -print0)
}

prepare_archive() {
    local package=$1 archive=$2 sha256=$3 url=$4

    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
}

make_install() {
    make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \
        \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
}

meson_install() {
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
}

cmake_install() {
    cmake --build "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" cmake --install "$PACKAGE_BUILD"
    prune_translations "$PACKAGE_STAGING"
}

build_release() {
    local component=$1 version=$2 sha256=$3 archive=$4 url=$5
    shift 5
    local package="$component-$version"

    restore_package "$package" && return 0
    prepare_archive "$package" "$archive" "$sha256" "$url"
    if [[ -x "$PACKAGE_SOURCE/configure" ]]; then
        graphical_release_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
            --disable-static \
            --disable-silent-rules \
            --sysconfdir=/etc \
            "$@"
    else
        graphical_autotools_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
            --disable-static \
            --disable-silent-rules \
            --sysconfdir=/etc \
            "$@"
    fi
    make_install
    publish_package "$package"
}

package="xfce4-terminal-$XFCE4_TERMINAL_VERSION"
if ! restore_package "$package"; then
    prepare_archive \
        "$package" "$package.tar.xz" "$XFCE4_TERMINAL_SHA256" \
        "https://archive.xfce.org/src/apps/xfce4-terminal/1.1/$package.tar.xz"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --sysconfdir=../etc \
        -Dx11=enabled \
        -Dwayland=disabled \
        -Dgtk-layer-shell=disabled \
        -Dlibutempter=disabled
    meson_install
    [[ ! -d "$PACKAGE_STAGING/usr/etc" ]] || \
        die "xfce4-terminal configuration leaked into /usr/etc"
    publish_package "$package"
fi

build_release \
    xfce4-notifyd "$XFCE4_NOTIFYD_VERSION" "$XFCE4_NOTIFYD_SHA256" \
    "xfce4-notifyd-$XFCE4_NOTIFYD_VERSION.tar.bz2" \
    "https://archive.xfce.org/src/apps/xfce4-notifyd/0.8/xfce4-notifyd-$XFCE4_NOTIFYD_VERSION.tar.bz2" \
    --enable-gdk-x11 \
    --disable-gdk-wayland \
    --disable-gtk-layer-shell \
    --disable-sound \
    --disable-canberra \
    --disable-dbus-start-daemon \
    --disable-debug

build_release \
    xfce4-power-manager "$XFCE4_POWER_MANAGER_VERSION" "$XFCE4_POWER_MANAGER_SHA256" \
    "xfce4-power-manager-$XFCE4_POWER_MANAGER_VERSION.tar.bz2" \
    "https://archive.xfce.org/src/xfce/xfce4-power-manager/4.18/xfce4-power-manager-$XFCE4_POWER_MANAGER_VERSION.tar.bz2" \
    --enable-polkit \
    --enable-network-manager \
    --enable-panel-plugins \
    --with-backend=linux \
    --disable-debug

build_release \
    xfce4-screensaver "$XFCE4_SCREENSAVER_VERSION" "$XFCE4_SCREENSAVER_SHA256" \
    "xfce4-screensaver-$XFCE4_SCREENSAVER_VERSION.tar.bz2" \
    "https://archive.xfce.org/src/apps/xfce4-screensaver/4.18/xfce4-screensaver-$XFCE4_SCREENSAVER_VERSION.tar.bz2" \
    --enable-locking \
    --enable-pam \
    --with-pam-prefix=/etc \
    --with-pam-auth-type=system-auth \
    --without-console-kit \
    --without-systemd \
    --with-elogind \
    --without-kbd-layout-indicator \
    --without-xscreensaverdir \
    --without-xscreensaverhackdir \
    --without-libgl \
    --disable-docbook-docs

build_release \
    xfce4-pulseaudio-plugin "$XFCE4_PULSEAUDIO_PLUGIN_VERSION" "$XFCE4_PULSEAUDIO_PLUGIN_SHA256" \
    "xfce4-pulseaudio-plugin-$XFCE4_PULSEAUDIO_PLUGIN_VERSION.tar.bz2" \
    "https://archive.xfce.org/src/panel-plugins/xfce4-pulseaudio-plugin/0.4/xfce4-pulseaudio-plugin-$XFCE4_PULSEAUDIO_PLUGIN_VERSION.tar.bz2" \
    --disable-keybinder \
    --enable-libnotify \
    --disable-libcanberra \
    --disable-mpris2 \
    --disable-libxfce4windowing \
    --enable-wnck \
    --with-mixer-command=/usr/bin/efilinux-volume-control \
    --disable-debug

build_release \
    thunar-volman "$THUNAR_VOLMAN_VERSION" "$THUNAR_VOLMAN_SHA256" \
    "thunar-volman-$THUNAR_VOLMAN_VERSION.tar.bz2" \
    "https://archive.xfce.org/src/xfce/thunar-volman/4.18/thunar-volman-$THUNAR_VOLMAN_VERSION.tar.bz2" \
    --enable-notifications \
    --disable-debug

package="xfce4-whiskermenu-plugin-$XFCE4_WHISKERMENU_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.bz2" "$XFCE4_WHISKERMENU_SHA256" \
        "https://archive.xfce.org/src/panel-plugins/xfce4-whiskermenu-plugin/2.8/$package.tar.bz2"
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        graphical_cmake_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        -DENABLE_ACCOUNTS_SERVICE=OFF \
        -DENABLE_GTK_LAYER_SHELL=OFF \
        -DENABLE_STRIP=OFF \
        -DENABLE_DEVELOPER_MODE=OFF
    cmake_install
    publish_package "$package"
fi

package="xfce-polkit-$XFCE_POLKIT_VERSION"
if ! restore_package "$package"; then
    prepare_archive \
        "$package" "xfce-polkit-$XFCE_POLKIT_COMMIT.tar.gz" \
        "$XFCE_POLKIT_SHA256" \
        "https://github.com/ncopa/xfce-polkit/archive/$XFCE_POLKIT_COMMIT.tar.gz"
    sed -i \
        "s/sysconfdir = join_paths(prefix, get_option('sysconfdir'))/sysconfdir = get_option('sysconfdir')/" \
        "$PACKAGE_SOURCE/meson.build"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --sysconfdir=/etc \
        --libexecdir=lib/xfce-polkit
    meson_install
    [[ -x "$PACKAGE_STAGING/usr/lib/xfce-polkit/xfce-polkit" ]] || \
        die "xfce-polkit authentication agent is missing"
    [[ -f "$PACKAGE_STAGING/etc/xdg/autostart/xfce-polkit.desktop" ]] || \
        die "xfce-polkit autostart entry is missing"
    [[ ! -d "$PACKAGE_STAGING/usr/etc" ]] || \
        die "xfce-polkit configuration leaked into /usr/etc"
    publish_package "$package"
fi

package="libnma-$LIBNMA_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.xz" "$LIBNMA_SHA256" \
        "https://download.gnome.org/sources/libnma/${LIBNMA_VERSION%.*}/$package.tar.xz"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        -Dlibnma_gtk4=false \
        -Dgcr=false \
        -Diso_codes=false \
        -Dmobile_broadband_provider_info=false \
        -Dgtk_doc=false \
        -Dintrospection=false \
        -Dvapi=false \
        -Dmore_asserts=0
    meson_install
    publish_package "$package"
fi

package="network-manager-applet-$NM_APPLET_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.xz" "$NM_APPLET_SHA256" \
        "https://download.gnome.org/sources/network-manager-applet/${NM_APPLET_VERSION%.*}/$package.tar.xz"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        -Dappindicator=no \
        -Dwwan=false \
        -Dselinux=false \
        -Dteam=false \
        -Dmore_asserts=0
    meson_install
    publish_package "$package"
fi
