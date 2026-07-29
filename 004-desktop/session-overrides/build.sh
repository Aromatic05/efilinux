#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/003-graphical/desktop-support/config.sh"
source "$ROOT/003-graphical/session-support/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command curl find gcc make pkg-config sha256sum tar
ensure_directories

"$ROOT/004-desktop/host-tools/build.sh"
export PATH="$EFILINUX_BUILD/host-tools/intltool-$INTLTOOL_VERSION/bin:$PATH"
require_command intltool-extract intltool-merge intltool-update

recipe_inputs=(
    "$ROOT/001-runtime/config.sh"
    "$ROOT/002-system/desktop-config.sh"
    "$ROOT/003-graphical/config.sh"
    "$ROOT/003-graphical/desktop-support/config.sh"
    "$ROOT/003-graphical/session-support/config.sh"
    "$ROOT/004-desktop/config.sh"
)

build_override() {
    local component=$1 version=$2 sha256=$3
    shift 3
    local package="$component-$version"
    local archive="$component-$version.tar.bz2"

    set_package_paths "$package"
    if binary_package_restore_sysroot \
        "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"; then
        return
    fi

    graphical_prepare_archive \
        "$package" "$archive" "$sha256" \
        "https://archive.xfce.org/src/xfce/$component/4.18/$archive"
    graphical_release_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --disable-silent-rules \
        --sysconfdir=/etc \
        "$@"
    env -u LD_LIBRARY_PATH make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    env -u LD_LIBRARY_PATH make -C "$PACKAGE_BUILD" \
        DESTDIR="$PACKAGE_STAGING" install
    find "$PACKAGE_STAGING" -type f -name '*.la' -delete 2>/dev/null || true
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    binary_package_publish_sysroot \
        "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

export ICEAUTH=/usr/bin/iceauth
build_override \
    xfce4-session "$XFCE4_SESSION_VERSION" "$XFCE4_SESSION_SHA256" \
    --enable-polkit \
    --disable-debug
unset ICEAUTH

build_override \
    xfce4-settings "$XFCE4_SETTINGS_VERSION" "$XFCE4_SETTINGS_SHA256" \
    --enable-xrandr \
    --enable-upower-glib \
    --enable-libnotify \
    --disable-colord \
    --enable-gio-unix \
    --enable-libxklavier \
    --disable-sound-settings \
    --disable-debug
