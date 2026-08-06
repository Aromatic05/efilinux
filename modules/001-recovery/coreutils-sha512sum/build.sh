#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=coreutils-sha512sum
pkgver=9.11
depends=(coreutils glibc)
builddepends=()
makedepends=(readelf)

prepare() { :; }

build() {
    install -Dm0755 "$EFILINUX_SYSROOT/usr/bin/sha512sum" \
        "$develdir/usr/bin/sha512sum"
}

check() {
    [[ -x "$develdir/usr/bin/sha512sum" ]] || die "sha512sum runtime is missing"
    readelf -d "$develdir/usr/bin/sha512sum" >/dev/null
}

package() {
    package_keep /usr/bin/sha512sum
}

recipe_main "$@"
