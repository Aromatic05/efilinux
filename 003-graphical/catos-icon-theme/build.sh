#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=catos-icon-theme
pkgver=1
sysroot=false

depends=(hicolor-icon-theme papirus-maia-icon-theme)
builddepends=()
makedepends=(install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    local theme="$develdir/usr/share/icons/CatOS-Papirus-Dark-Maia"
    local apps="$theme/scalable/apps"
    local name

    install -d -m0755 "$apps" "$develdir/usr/share/icons/hicolor/scalable/apps"
    cat > "$theme/index.theme" <<'THEME'
[Icon Theme]
Name=CatOS Papirus Dark Maia
Comment=CatOS branding over Papirus Dark Maia
Inherits=Papirus-Dark-Maia
Directories=scalable/apps

[scalable/apps]
Size=48
Context=Applications
Type=Scalable
MinSize=16
MaxSize=512
THEME

    install -m0644 "$srcdir/files/catos-logo.svg" "$apps/catos-logo.svg"
    for name in start-here distributor-logo system-logo xfce4-logo org.xfce.panel.whiskermenu; do
        ln -s catos-logo.svg "$apps/$name.svg"
    done

    install -m0644 "$srcdir/files/catos-logo.svg" \
        "$develdir/usr/share/icons/hicolor/scalable/apps/catos-logo.svg"
    install -m0644 "$srcdir/files/catos-logo.svg" \
        "$develdir/usr/share/icons/whiskermenu-catos.svg"
}

package() { :; }

recipe_main "$@"
