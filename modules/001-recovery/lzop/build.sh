#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=lzop
pkgver=1.04
depends=(glibc lzo)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/lzop-$pkgver.tar.gz"
    download "https://www.lzop.org/download/lzop-$pkgver.tar.gz" "$archive"
    checksum sha256 7e72b62a8a60aff5200a047eea0773a8fb205caf7acbe1774d95147f305a2f41 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    target_release_configure "$srcdir/source" "$builddir"
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin/lzop"; }
package() { package_keep /usr/bin/lzop; }
recipe_main "$@"
