#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=file
pkgver=5.48
depends=(glibc zlib)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/file-$pkgver.tar.gz"
    download "https://astron.com/pub/file/file-$pkgver.tar.gz" "$archive"
    checksum sha256 ed14656883b23a364b4057c05595d93252da9bc473d30106519519d0da141283 "$archive"
    extract "$archive" "$srcdir/file"
}

build() {
    cd "$builddir"
    target_env "$srcdir/file/configure" --prefix=/usr --libdir=/usr/lib \
        --disable-static --disable-libseccomp --disable-python
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }

package() {
    local -a keep=(/usr/bin/file /usr/share/misc/magic.mgc)
    package_add_library_family keep 'libmagic.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
