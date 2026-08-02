#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=libisofs
pkgver=1.5.6
depends=(acl glibc zlib)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/libisofs-$pkgver.tar.gz"
    download "https://files.libburnia-project.org/releases/libisofs-$pkgver.tar.gz" "$archive"
    checksum sha256 0152d66a9d340b659fe9c880eb9190f3570fb477ac07cf52e8bcd134a1d30d70 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --enable-shared
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/lib"
}
package() {
    local -a keep=()
    package_add_library_family keep 'libisofs.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
