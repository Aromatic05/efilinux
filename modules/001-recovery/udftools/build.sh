#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=udftools
pkgver=2.3
depends=(glibc readline udev)
builddepends=()
makedepends=(autoconf automake gcc make pkg-config)
prepare() {
    local archive="$downloaddir/udftools-$pkgver.tar.gz"
    download "https://github.com/pali/udftools/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 095e1c8b947849f5f8a1cade23dd3375532bda305a184eb022df96e43c4d6f7e "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/out-of-tree-pktsetup-include.patch" \
        "$srcdir/out-of-tree-pktsetup-include.patch"
    input_file "$recipedir/files/pkg-config-udevdir-sysroot.patch" \
        "$srcdir/pkg-config-udevdir-sysroot.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/out-of-tree-pktsetup-include.patch"
    patch -d "$srcdir/source" -Np1 -i "$srcdir/pkg-config-udevdir-sysroot.patch"
    (cd "$srcdir/source" && autoreconf -fi)
}
build() {
    target_release_configure "$srcdir/source" "$builddir" --sbindir=/usr/bin
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin"; }
package() {
    package_keep \
        /usr/bin/cdrwtool \
        /usr/bin/mkudffs \
        /usr/bin/pktsetup \
        /usr/bin/udfinfo \
        /usr/bin/udflabel
}
recipe_main "$@"
