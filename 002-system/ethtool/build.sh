#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=ethtool
pkgver=7.1
sysroot=false

depends=(glibc libmnl)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/ethtool-$pkgver.tar.xz"
    download "https://www.kernel.org/pub/software/network/ethtool/ethtool-$pkgver.tar.xz" "$archive"
    checksum sha256 4d78c26edc0255bc92f4b995b5fd66108d75ff966ed4694f6025a6d370bc2496 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --sbindir=/usr/bin
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin/ethtool"
}

package() {
    package_keep /usr/bin/ethtool
}

recipe_main "$@"
