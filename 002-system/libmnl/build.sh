#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libmnl
pkgver=1.0.5

depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libmnl-$pkgver.tar.bz2"
    download "https://www.netfilter.org/projects/libmnl/files/libmnl-$pkgver.tar.bz2" "$archive"
    checksum sha256 274b9b919ef3152bfb3da3a13c950dd60d6e2bcd54230ffeca298d03b40d0525 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static
    target_make_install "$builddir" "$develdir"
}

devel() {
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libmnl.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
