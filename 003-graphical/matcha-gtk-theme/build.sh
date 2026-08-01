#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=matcha-gtk-theme
pkgver=2025-04-11
sysroot=false

depends=()
builddepends=()
makedepends=(install)

prepare() {
    local archive="$downloaddir/matcha-gtk-theme-$pkgver.tar.gz"
    download "https://github.com/vinceliuice/Matcha-gtk-theme/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 8a3f71a3b9fd4907b28686e228e337d27742018e6dfa8e338326fe77115f5ea7 "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    local source="$srcdir/source/src"
    local theme="$develdir/usr/share/themes/Matcha-dark-sea"

    install -d -m0755 \
        "$theme/gtk-2.0" \
        "$theme/gtk-3.0" \
        "$theme/gtk-4.0" \
        "$theme/xfwm4"

    install -m0644 \
        "$source/gtk-2.0/apps.rc" \
        "$source/gtk-2.0/main.rc" \
        "$source/gtk-2.0/panel.rc" \
        "$source/gtk-2.0/xfce-notify.rc" \
        "$theme/gtk-2.0/"
    install -m0644 "$source/gtk-2.0/gtkrc-dark-sea" \
        "$theme/gtk-2.0/gtkrc"
    install -m0644 "$source/gtk-2.0/menubar-toolbar-dark.rc" \
        "$theme/gtk-2.0/menubar-toolbar.rc"
    cp -a "$source/gtk-2.0/assets-dark-sea" "$theme/gtk-2.0/assets"

    cp -a "$source/gtk/assets-sea" "$theme/gtk-3.0/assets"
    install -m0644 "$source/gtk/gtk-3.0/gtk-dark-sea.css" \
        "$theme/gtk-3.0/gtk.css"
    install -m0644 "$source/gtk/gtk-3.0/gtk-dark-sea.css" \
        "$theme/gtk-3.0/gtk-dark.css"
    install -m0644 "$source/gtk/thumbnail-dark-sea.png" \
        "$theme/gtk-3.0/thumbnail.png"

    ln -s ../gtk-3.0/assets "$theme/gtk-4.0/assets"
    install -m0644 "$source/gtk/gtk-4.0/gtk-dark-sea.css" \
        "$theme/gtk-4.0/gtk.css"
    install -m0644 "$source/gtk/gtk-4.0/gtk-dark-sea.css" \
        "$theme/gtk-4.0/gtk-dark.css"
    ln -s ../gtk-3.0/thumbnail.png "$theme/gtk-4.0/thumbnail.png"

    cp -a "$source/xfwm4/assets-dark-sea/." "$theme/xfwm4/"
    install -m0644 "$source/xfwm4/themerc-sea" "$theme/xfwm4/themerc"

    cat > "$theme/index.theme" <<'INDEX'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Matcha-dark-sea
Comment=Dark Matcha theme for Xfce
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Matcha-dark-sea
MetacityTheme=Matcha-dark-sea
IconTheme=CatOS-Papirus-Dark-Maia
CursorTheme=breeze-cursors
ButtonLayout=menu:minimize,maximize,close
INDEX
}

package() {
    package_keep /usr/share/themes/Matcha-dark-sea/
}

recipe_main "$@"
