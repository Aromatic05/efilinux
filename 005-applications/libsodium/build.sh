#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libsodium
pkgver=1.0.22
depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/libsodium-$pkgver.tar.gz"
    download "https://download.libsodium.org/libsodium/releases/libsodium-$pkgver.tar.gz" "$archive"
    checksum sha256 adbdd8f16149e81ac6078a03aca6fc03b592b89ef7b5ed83841c086191be3349 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --disable-dependency-tracking \
        --disable-ssp \
        --enable-minimal
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libsodium.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
