#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=ncurses-panelw
pkgver=6.6
depends=(glibc ncurses)
builddepends=()
makedepends=(readelf)
prepare() { :; }
build() {
    install -Dm0755 "$EFILINUX_SYSROOT/usr/lib/libpanelw.so.6.6" \
        "$develdir/usr/lib/libpanelw.so.6.6"
    ln -s libpanelw.so.6.6 "$develdir/usr/lib/libpanelw.so.6"
}
check() {
    [[ -f "$develdir/usr/lib/libpanelw.so.6.6" ]] || die "ncurses panel runtime is missing"
    readelf -d "$develdir/usr/lib/libpanelw.so.6.6" >/dev/null
}
package() {
    local -a keep=()
    package_add_library_family keep 'libpanelw.so.6*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
