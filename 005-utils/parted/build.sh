#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=parted
pkgver=3.7
depends=(device-mapper glibc readline util-linux)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/parted-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/parted/parted-$pkgver.tar.xz" "$archive"
    checksum sha256 008de57561a4f3c25a0648e66ed11e7b30be493889b64334a6d70f2c1951ef7b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }

package() {
    local -a keep=(/usr/bin/parted)
    package_add_library_family keep 'libparted.so.2*'
    [[ ! -d "$pkgdir/usr/share/parted" ]] || keep+=(/usr/share/parted/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
