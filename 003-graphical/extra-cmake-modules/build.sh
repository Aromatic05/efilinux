#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=extra-cmake-modules
pkgver=5.116.0
depends=()
builddepends=()
makedepends=(cmake ninja)

prepare() {
    local archive="$downloaddir/extra-cmake-modules-$pkgver.tar.gz"
    download "https://github.com/KDE/extra-cmake-modules/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 9ba50fd22ad40441e40ba0dcf3227491e0a196163f481751b0130acb359d4568 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" -DBUILD_TESTING=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() { :; }

package() {
    package_keep /usr/share/ECM/
}

recipe_main "$@"
