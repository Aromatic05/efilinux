#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=wimlib
pkgver=1.14.5
depends=(fuse glibc ntfs-3g)
builddepends=()
makedepends=(autoconf automake gcc libtool make pkg-config)
prepare() {
    local archive="$downloaddir/wimlib-$pkgver.tar.gz"
    download "https://github.com/ebiggers/wimlib/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 5f9416b3750c29d6ad35a2fc3bd6697807566ee287b28e004b0111c3787b1ce2 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/tarball-version.patch" "$srcdir/tarball-version.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/tarball-version.patch"
}
build() {
    target_autotools_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --disable-test-support \
        --with-ntfs-3g \
        --with-fuse
    target_make_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(/usr/bin/)
    package_add_library_family keep 'libwim.so.*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
