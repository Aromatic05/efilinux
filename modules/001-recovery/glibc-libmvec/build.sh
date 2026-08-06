#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=glibc-libmvec
pkgver=2.43
depends=(glibc)
builddepends=()
makedepends=(readelf)
prepare() { :; }
build() {
    install -Dm0755 "$EFILINUX_SYSROOT/usr/lib/libmvec.so.1" \
        "$develdir/usr/lib/libmvec.so.1"
}
check() {
    [[ -f "$develdir/usr/lib/libmvec.so.1" ]] || die "glibc libmvec runtime is missing"
    readelf -d "$develdir/usr/lib/libmvec.so.1" >/dev/null
}
package() { package_keep /usr/lib/libmvec.so.1; }
recipe_main "$@"
