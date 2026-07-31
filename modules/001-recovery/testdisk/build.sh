#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=testdisk
pkgver=7.2
depends=(bzip2 e2fsprogs glibc libjpeg-turbo ncurses ntfs-3g util-linux zlib)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/testdisk-$pkgver.tar.bz2"
    download "https://www.cgsecurity.org/testdisk-$pkgver.tar.bz2" "$archive"
    checksum sha256 f8343be20cb4001c5d91a2e3bcd918398f00ae6d8310894a5a9f2feb813c283f "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --disable-qt \
        --disable-sudo \
        --disable-dfxml \
        --disable-assert \
        --disable-record-compilation-date \
        --with-ncurses \
        --with-ext2fs \
        --with-jpeg \
        --with-ntfs3g \
        --with-zlib \
        --with-uuid \
        --without-ewf \
        --without-reiserfs
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin"; }
package() {
    package_keep /usr/bin/testdisk /usr/bin/photorec /usr/bin/fidentify
}
recipe_main "$@"
