#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command curl gcc meson ninja pkg-config python3 sha256sum tar
ensure_directories

build_meson_component() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    if graphical_binary_package_restore "$package"; then
        return
    fi
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
}

build_meson_component \
    "libevdev-$LIBEVDEV_VERSION" \
    "libevdev-$LIBEVDEV_VERSION.tar.gz" \
    "$LIBEVDEV_SHA256" \
    "https://gitlab.freedesktop.org/libevdev/libevdev/-/archive/libevdev-$LIBEVDEV_VERSION/libevdev-libevdev-$LIBEVDEV_VERSION.tar.gz" \
    -Dtests=disabled \
    -Dtools=disabled \
    -Ddocumentation=disabled

build_meson_component \
    "libinput-$LIBINPUT_VERSION" \
    "libinput-$LIBINPUT_VERSION.tar.gz" \
    "$LIBINPUT_SHA256" \
    "https://gitlab.freedesktop.org/libinput/libinput/-/archive/$LIBINPUT_VERSION/libinput-$LIBINPUT_VERSION.tar.gz" \
    -Dlibwacom=false \
    -Dmtdev=false \
    -Ddebug-gui=false \
    -Dtests=false \
    -Dinstall-tests=false \
    -Ddocumentation=false \
    -Dzshcompletiondir=no \
    -Dlua-plugins=disabled \
    -Dinternal-event-debugging=false \
    -Dautoload-plugins=false

build_meson_component \
    "xkeyboard-config-$XKEYBOARD_CONFIG_VERSION" \
    "xkeyboard-config-$XKEYBOARD_CONFIG_VERSION.tar.gz" \
    "$XKEYBOARD_CONFIG_SHA256" \
    "https://gitlab.freedesktop.org/xkeyboard-config/xkeyboard-config/-/archive/xkeyboard-config-$XKEYBOARD_CONFIG_VERSION/xkeyboard-config-xkeyboard-config-$XKEYBOARD_CONFIG_VERSION.tar.gz" \
    -Dcompat-rules=true \
    -Dxorg-rules-symlinks=true \
    -Dnls=false \
    -Dnon-latin-layouts-list=false

build_meson_component \
    "libxkbcommon-$LIBXKBCOMMON_VERSION" \
    "libxkbcommon-$LIBXKBCOMMON_VERSION.tar.gz" \
    "$LIBXKBCOMMON_SHA256" \
    "https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-$LIBXKBCOMMON_VERSION.tar.gz" \
    -Denable-tools=false \
    -Denable-x11=true \
    -Denable-docs=false \
    -Denable-wayland=false \
    -Denable-xkbregistry=false \
    -Denable-bash-completion=false \
    -Ddefault-rules=evdev \
    -Ddefault-model=pc105 \
    -Ddefault-layout=us

for artifact in \
    usr/lib/libevdev.so.2 \
    usr/lib/libinput.so.10 \
    usr/lib/libxkbcommon.so.0 \
    usr/lib/libxkbcommon-x11.so.0 \
    usr/share/X11/xkb/rules/evdev; do
    [[ -e "$EFILINUX_SYSROOT/$artifact" ]] || \
        die "input stack artifact is missing: /$artifact"
done

for dependency in libevdev libinput xkeyboard-config xkbcommon xkbcommon-x11; do
    target_pkg_config --exists "$dependency" || \
        die "input stack pkg-config dependency is missing: $dependency"
done

if find "$EFILINUX_SYSROOT" -iname '*wayland*' -print -quit | grep -q .; then
    die "Wayland artifacts leaked into the input stack sysroot"
fi
