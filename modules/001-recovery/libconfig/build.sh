#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libconfig
pkgver=1.8.2
depends=(glibc)
builddepends=()
makedepends=(autoconf automake gcc make)
prepare() {
    local archive="$downloaddir/libconfig-$pkgver.tar.gz"
    download "https://github.com/hyperrealm/libconfig/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 8e71983761b08c65b15b769b3ec1d980036c461fdfd415c7183378a4b3eac8f4 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_autotools_configure "$srcdir/source" "$builddir" \
        --disable-cxx \
        --disable-examples \
        --disable-tests
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libconfig.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
