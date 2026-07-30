#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/003-graphical/desktop-support/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"
source "$ROOT/004-desktop/lib/build.sh"

require_command curl find gcc make pkg-config sha256sum tar
ensure_directories
producer="${BASH_SOURCE[0]}"

require_command intltool-extract intltool-merge intltool-update

log "Building XFCE 4.18 foundation libraries"
desktop_release_build \
    libxfce4util "$LIBXFCE4UTIL_VERSION" "$LIBXFCE4UTIL_SHA256" "$producer" \
    --disable-gtk-doc \
    --disable-introspection \
    --disable-debug

desktop_release_build \
    xfconf "$XFCONF_VERSION" "$XFCONF_SHA256" "$producer" \
    --disable-gtk-doc \
    --disable-introspection \
    --disable-debug

desktop_release_build \
    libxfce4ui "$LIBXFCE4UI_VERSION" "$LIBXFCE4UI_SHA256" "$producer" \
    --enable-gudev \
    --enable-startup-notification \
    --disable-introspection \
    --disable-gtk-doc \
    --disable-debug

desktop_release_build \
    exo "$EXO_VERSION" "$EXO_SHA256" "$producer" \
    --enable-gio-unix \
    --disable-gtk-doc \
    --disable-debug

desktop_release_build \
    garcon "$GARCON_VERSION" "$GARCON_SHA256" "$producer" \
    --disable-introspection \
    --disable-gtk-doc \
    --disable-debug

log "Building XFCE file manager and thumbnail service"
desktop_release_build \
    thunar "$THUNAR_VERSION" "$THUNAR_SHA256" "$producer" \
    --disable-introspection \
    --disable-gtk-doc \
    --enable-gio-unix \
    --enable-gudev \
    --enable-notifications \
    --enable-exif \
    --enable-pcre2 \
    --disable-debug

desktop_release_build \
    tumbler "$TUMBLER_VERSION" "$TUMBLER_SHA256" "$producer" \
    --disable-gtk-doc \
    --disable-cover-thumbnailer \
    --disable-ffmpeg-thumbnailer \
    --disable-gstreamer-thumbnailer \
    --disable-odf-thumbnailer \
    --disable-poppler-thumbnailer \
    --disable-raw-thumbnailer \
    --disable-gepub-thumbnailer \
    --disable-debug

log "Building XFCE shell, session, settings, desktop, and window manager"
desktop_release_build \
    xfce4-appfinder "$XFCE4_APPFINDER_VERSION" "$XFCE4_APPFINDER_SHA256" "$producer" \
    --disable-debug

desktop_release_build \
    xfce4-panel "$XFCE4_PANEL_VERSION" "$XFCE4_PANEL_SHA256" "$producer" \
    --disable-dbusmenu-gtk3 \
    --enable-gio-unix \
    --disable-introspection \
    --disable-vala \
    --disable-gtk-doc \
    --disable-debug

export ICEAUTH=/usr/bin/iceauth
desktop_release_build \
    xfce4-session "$XFCE4_SESSION_VERSION" "$XFCE4_SESSION_SHA256" "$producer" \
    --disable-polkit \
    --disable-debug
unset ICEAUTH

desktop_release_build \
    xfce4-settings "$XFCE4_SETTINGS_VERSION" "$XFCE4_SETTINGS_SHA256" "$producer" \
    --enable-xrandr \
    --disable-upower-glib \
    --enable-libnotify \
    --disable-colord \
    --enable-gio-unix \
    --disable-libxklavier \
    --disable-sound-settings \
    --disable-debug

desktop_release_build \
    xfdesktop "$XFDESKTOP_VERSION" "$XFDESKTOP_SHA256" "$producer" \
    --enable-thunarx \
    --enable-notifications \
    --disable-debug

desktop_release_build \
    xfwm4 "$XFWM4_VERSION" "$XFWM4_SHA256" "$producer" \
    --enable-startup-notification \
    --enable-xpresent \
    --enable-compositor \
    --disable-debug
