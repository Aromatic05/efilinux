#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=libxkbcommon-x11
pkgver=1.13.2
depends=(glibc libxkbcommon xorg)
builddepends=()
makedepends=(readelf)
prepare() { :; }
build() {
    install -Dm0755 "$EFILINUX_SYSROOT/usr/lib/libxkbcommon-x11.so.0.13.2" \
        "$develdir/usr/lib/libxkbcommon-x11.so.0.13.2"
    ln -s libxkbcommon-x11.so.0.13.2 "$develdir/usr/lib/libxkbcommon-x11.so.0"
}
check() {
    [[ -f "$develdir/usr/lib/libxkbcommon-x11.so.0.13.2" ]] ||
        die "libxkbcommon X11 runtime is missing"
    readelf -d "$develdir/usr/lib/libxkbcommon-x11.so.0.13.2" >/dev/null
}
package() {
    local -a keep=()
    package_add_library_family keep 'libxkbcommon-x11.so.0*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
