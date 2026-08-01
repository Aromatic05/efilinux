#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=efilinux-graphical-config
pkgver=1
sysroot=false

depends=(
    breeze-cursor-theme efilinux-system-config gtk3 catos-icon-theme matcha-gtk-theme
    papirus-icon-theme papirus-maia-icon-theme xorg-server
)
builddepends=()
makedepends=(find install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    local runlevel

    cp -a "$srcdir/files/." "$develdir/"
    find "$develdir/etc" -type f -exec chmod 0644 {} +
    chmod 0755 "$develdir/etc/X11/xinit/xinitrc" "$develdir/etc/rc.d/init.d/graphical"

    install -d -m0755 \
        "$develdir/usr/share/X11/xorg.conf.d" \
        "$develdir/etc/rc.d/rc5.d" \
        "$develdir/run/user" \
        "$develdir/var/cache/fontconfig" \
        "$develdir/var/lib/xkb" \
        "$develdir/var/log"
    touch "$develdir/var/log/graphical.log"
    chmod 0644 "$develdir/var/log/graphical.log"

    ln -s ../../usr/share/X11/xorg.conf.d "$develdir/etc/X11/xorg.conf.d"
    ln -s ../init.d/graphical "$develdir/etc/rc.d/rc5.d/S80graphical"
    for runlevel in 0 1 2 3 4 6; do
        install -d -m0755 "$develdir/etc/rc.d/rc${runlevel}.d"
        ln -s ../init.d/graphical "$develdir/etc/rc.d/rc${runlevel}.d/K05graphical"
    done
}

package() { :; }

recipe_main "$@"
