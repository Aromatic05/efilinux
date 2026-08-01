#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libtirpc
pkgver=1.3.7
depends=(glibc krb5)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libtirpc-$pkgver.tar.bz2"
    download "https://downloads.sourceforge.net/project/libtirpc/libtirpc/$pkgver/libtirpc-$pkgver.tar.bz2" "$archive"
    checksum sha256 b47d3ac19d3549e54a05d0019a6c400674da716123858cfdb6d3bdd70a66c702 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/module-netconfig-path.patch" \
        "$srcdir/module-netconfig-path.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/module-netconfig-path.patch"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --enable-gssapi \
        --disable-authdes
    target_make_install "$builddir" "$develdir"
    install -Dm0644 "$srcdir/source/doc/netconfig" \
        "$develdir/opt/recovery/etc/netconfig"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libtirpc.so.*'
    keep+=(/opt/recovery/etc/netconfig)
    package_keep "${keep[@]}"
}

recipe_main "$@"
