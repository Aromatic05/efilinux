#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libuv
pkgver=1.51.0
depends=(glibc)
builddepends=()
makedepends=(cmake gcc ninja pkg-config)

prepare() {
    local archive="$downloaddir/libuv-$pkgver.tar.gz"
    download "https://github.com/libuv/libuv/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 27e55cf7083913bfb6826ca78cde9de7647cded648d35f24163f2d31bb9f51cd "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_TESTING=OFF \
        -DLIBUV_BUILD_TESTS=OFF \
        -DLIBUV_BUILD_BENCH=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    local opt_lib="$develdir/opt/fcitx5/lib"

    install -d -m0755 "$opt_lib"
    find "$develdir/usr/lib" -maxdepth 1 \
        \( -type f -o -type l \) \
        \( -name 'libuv.so*' \) \
        -exec cp -a -t "$opt_lib" {} +
    strip_all "$develdir/usr/lib" "$opt_lib"
}

package() {
    local path
    local -a keep=()

    while IFS= read -r -d '' path; do
        keep+=("${path#$pkgdir}")
    done < <(find "$pkgdir/opt/fcitx5/lib" -maxdepth 1 \
        \( -type f -o -type l \) \
        \( -name 'libuv.so*' \) -print0)
    ((${#keep[@]} > 0)) || die "runtime libraries are missing for libuv"
    package_keep "${keep[@]}"
}

recipe_main "$@"
