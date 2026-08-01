#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libevent
pkgver=2.1.12-stable
depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libevent-$pkgver.tar.gz"
    download "https://github.com/libevent/libevent/releases/download/release-$pkgver/libevent-$pkgver.tar.gz" "$archive"
    checksum sha256 92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --disable-openssl \
        --disable-debug-mode \
        --disable-libevent-regress \
        --disable-samples
    target_make_install "$builddir" "$develdir"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    local family
    for family in \
        'libevent-*.so.*' \
        'libevent_core-*.so.*' \
        'libevent_extra-*.so.*' \
        'libevent_pthreads-*.so.*'; do
        package_add_library_family keep "$family"
    done
    package_keep "${keep[@]}"
}

recipe_main "$@"
