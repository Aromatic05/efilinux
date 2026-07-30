#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=qogir-desktop-theme
pkgver=2025-08-17
sysroot=false

depends=()
builddepends=()
makedepends=(install)

prepare() {
    local archive="$downloaddir/qogir-theme-$pkgver.tar.gz"
    download "https://github.com/vinceliuice/Qogir-theme/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 cc7a1a6f7449571251bbfd338e3e671254ba93bee41c5b997bf5a6626faaae8f "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    local theme="$develdir/usr/share/themes/Qogir"
    mkdir -p "$theme/gtk-2.0/assets" "$theme/gtk-3.0/assets" "$theme/gtk-4.0/assets/scalable" "$theme/xfwm4"
    cat > "$theme/index.theme" <<'THEME'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Qogir
Comment=EFILinux Qogir desktop theme

[X-GNOME-Metatheme]
GtkTheme=Qogir
MetacityTheme=Qogir
IconTheme=Qogir
CursorTheme=Qogir
ButtonLayout=menu:minimize,maximize,close
THEME
    install -m0644 "$srcdir/source/src/gtk-2.0/theme/gtkrc" "$theme/gtk-2.0/gtkrc"
    install -m0644 "$srcdir/source/src/gtk-2.0/"*.rc "$theme/gtk-2.0/"
    cp -a "$srcdir/source/src/gtk-2.0/assets/assets/." "$theme/gtk-2.0/assets/"
    cp -a "$srcdir/source/src/gtk/assets/assets/." "$theme/gtk-3.0/assets/"
    cp -a "$srcdir/source/src/gtk/assets/assets-common/." "$theme/gtk-3.0/assets/"
    install -m0644 "$srcdir/source/src/gtk/assets/logos/logo-.svg" "$theme/gtk-3.0/assets/logo.svg"
    install -m0644 "$srcdir/source/src/gtk/assets/logos/logo@2-.svg" "$theme/gtk-3.0/assets/logo@2.svg"
    install -m0644 "$srcdir/source/src/gtk/theme-3.0/gtk.css" "$theme/gtk-3.0/gtk.css"
    install -m0644 "$srcdir/source/src/gtk/theme-3.0/gtk-Dark.css" "$theme/gtk-3.0/gtk-dark.css"
    install -m0644 "$srcdir/source/src/gtk/assets/thumbnail.png" "$theme/gtk-3.0/thumbnail.png"
    cp -a "$theme/gtk-3.0/assets/." "$theme/gtk-4.0/assets/"
    install -m0644 "$srcdir/source/src/gtk/assets/assets-common/check-symbolic.svg" "$srcdir/source/src/gtk/assets/assets-common/check-symbolic@2.svg" "$theme/gtk-4.0/assets/scalable/"
    install -m0644 "$srcdir/source/src/gtk/theme-4.0/gtk.css" "$theme/gtk-4.0/gtk.css"
    install -m0644 "$srcdir/source/src/gtk/theme-4.0/gtk-Dark.css" "$theme/gtk-4.0/gtk-dark.css"
    install -m0644 "$srcdir/source/src/xfwm4/themerc" "$theme/xfwm4/themerc"
    install -m0644 "$srcdir/source/src/xfwm4/assets/"*.png "$theme/xfwm4/"
    cp -a "$srcdir/source/src/xfce-notify-4.0" "$theme/xfce-notify-4.0"
}

package() { :; }

recipe_main "$@"
