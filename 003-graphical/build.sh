#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/003-graphical/libpng"
run_component "$ROOT/003-graphical/libjpeg-turbo"
run_component "$ROOT/003-graphical/freetype"
run_component "$ROOT/003-graphical/harfbuzz"
run_component "$ROOT/003-graphical/fontconfig"
run_component "$ROOT/003-graphical/fribidi"
run_component "$ROOT/003-graphical/pixman"
run_component "$ROOT/003-graphical/dejavu-fonts"

run_component "$ROOT/003-graphical/libpciaccess"
run_component "$ROOT/003-graphical/libdrm"
run_component "$ROOT/003-graphical/elfutils"
run_component "$ROOT/003-graphical/libevdev"
run_component "$ROOT/003-graphical/libinput"
run_component "$ROOT/003-graphical/xkeyboard-config"
run_component "$ROOT/003-graphical/xorg"
run_component "$ROOT/003-graphical/xorg-utils"
run_component "$ROOT/003-graphical/libxkbcommon"

run_component "$ROOT/003-graphical/mesa"
run_component "$ROOT/003-graphical/libepoxy"
run_component "$ROOT/003-graphical/xorg-server"

run_component "$ROOT/003-graphical/libxml2"
run_component "$ROOT/003-graphical/shared-mime-info"
run_component "$ROOT/003-graphical/desktop-file-utils"
run_component "$ROOT/003-graphical/hicolor-icon-theme"
run_component "$ROOT/003-graphical/at-spi2-core"
run_component "$ROOT/003-graphical/gdk-pixbuf"
run_component "$ROOT/003-graphical/cairo"
run_component "$ROOT/003-graphical/pango"
run_component "$ROOT/003-graphical/librsvg"
run_component "$ROOT/003-graphical/gtk3"
run_component "$ROOT/003-graphical/startup-notification"
run_component "$ROOT/003-graphical/libnotify"
run_component "$ROOT/003-graphical/libwnck"
run_component "$ROOT/003-graphical/iso-codes"
run_component "$ROOT/003-graphical/libxklavier"
run_component "$ROOT/003-graphical/dbus-glib"
run_component "$ROOT/003-graphical/vte"

run_component "$ROOT/003-graphical/noto-sans-cjk-sc"
run_component "$ROOT/003-graphical/qogir-icon-theme"
run_component "$ROOT/003-graphical/qogir-desktop-theme"
run_component "$ROOT/003-graphical/efilinux-graphical-config"
run_component "$ROOT/003-graphical/image"
