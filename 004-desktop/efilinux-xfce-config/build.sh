#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=efilinux-xfce-config
pkgver=1
sysroot=false

depends=(
    breeze-cursor-theme efilinux-system-config libnma linux-pam catos-icon-theme
    matcha-gtk-theme network-manager-applet papirus-icon-theme
    papirus-maia-icon-theme xfce xorg-server
)
builddepends=()
makedepends=(find install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    cp -a "$srcdir/files/." "$develdir/"
    find "$develdir/etc" -type f -exec chmod 0644 {} +
    chmod 0755 \
        "$develdir/etc/X11/xinit/xinitrc" \
        "$develdir/usr/bin/efilinux-audio-session" \
        "$develdir/usr/bin/efilinux-volume-control"

    install -d -m0755 \
        "$develdir/usr/share/X11/xorg.conf.d" \
        "$develdir/var/cache/fontconfig" \
        "$develdir/var/lib/xkb"

    ln -s ../../usr/share/X11/xorg.conf.d "$develdir/etc/X11/xorg.conf.d"

    install -d -m0750 "$develdir/home/user"
    cp -a "$develdir/etc/skel/." "$develdir/home/user/"
    install -d -m0755 "$develdir/home/user/Desktop" "$develdir/home/user/.cache"
    chown -R 1000:1000 "$develdir/home/user"
    chmod 0750 "$develdir/home/user"
}

package() {
    :
}

recipe_main "$@"
