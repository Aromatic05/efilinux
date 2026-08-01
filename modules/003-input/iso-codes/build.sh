#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=iso-codes
pkgver=4.20.1
depends=()
builddepends=()
makedepends=(meson ninja python3)

prepare() {
    local archive="$downloaddir/iso-codes-$pkgver.tar.gz"
    download "https://salsa.debian.org/iso-codes-team/iso-codes/-/archive/v$pkgver/iso-codes-v$pkgver.tar.gz" "$archive"
    checksum sha256 2d7d9f6084ab9ce6c534ce71a3dd5144b6e474f3c97616459a88f73f44a64bff "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir"
    target_meson_install "$builddir" "$develdir"
}

devel() { :; }

package() {
    package_keep /usr/share/iso-codes/json/
}

recipe_main "$@"
