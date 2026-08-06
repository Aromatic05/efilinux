#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=xdg-utils
pkgver=1.2.1

depends=(file)
builddepends=()
makedepends=(make)

prepare() {
    local archive="$downloaddir/xdg-utils-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/xdg/xdg-utils/-/archive/v$pkgver/xdg-utils-v$pkgver.tar.gz" \
        "$archive"
    checksum sha256 f6b648c064464c2636884c05746e80428110a576f8daacf46ef2e554dcfdae75 "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    local program
    (
        cd "$srcdir/source"
        ./configure --prefix=/usr
        for program in \
            xdg-desktop-icon xdg-desktop-menu xdg-email xdg-icon-resource \
            xdg-mime xdg-open xdg-screensaver xdg-settings; do
            : > "scripts/$program.txt"
        done
        make -C scripts -j"$EFILINUX_JOBS" scripts
    )
    for program in \
        xdg-desktop-icon xdg-desktop-menu xdg-email xdg-icon-resource \
        xdg-mime xdg-open xdg-screensaver xdg-settings; do
        install -Dm0755 "$srcdir/source/scripts/$program" \
            "$develdir/usr/bin/$program"
    done
}

check() {
    local program
    for program in \
        xdg-desktop-icon xdg-desktop-menu xdg-email xdg-icon-resource \
        xdg-mime xdg-open xdg-screensaver xdg-settings; do
        [[ -x "$develdir/usr/bin/$program" ]] ||
            die "xdg-utils program is missing: $program"
    done
}

package() {
    package_keep \
        /usr/bin/xdg-desktop-icon \
        /usr/bin/xdg-desktop-menu \
        /usr/bin/xdg-email \
        /usr/bin/xdg-icon-resource \
        /usr/bin/xdg-mime \
        /usr/bin/xdg-open \
        /usr/bin/xdg-screensaver \
        /usr/bin/xdg-settings
}

recipe_main "$@"
