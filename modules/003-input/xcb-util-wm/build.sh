#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xcb-util-wm
pkgver=0.4.2
depends=(glibc xorg)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/xcb-util-wm-$pkgver.tar.xz"
    download "https://xcb.freedesktop.org/dist/xcb-util-wm-$pkgver.tar.xz" "$archive"
    checksum sha256 62c34e21d06264687faea7edbf63632c9f04d55e72114aa4a57bb95e4f888a0b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --disable-devel-docs
    target_make_install "$builddir" "$develdir"
}

devel() {
    local opt_lib="$develdir/opt/fcitx5/lib"

    install -d -m0755 "$opt_lib"
    find "$develdir/usr/lib" -maxdepth 1 \
        \( -type f -o -type l \) \
        \( -name 'libxcb-icccm.so*' \
        -o -name 'libxcb-ewmh.so*' \) \
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
        \( -name 'libxcb-icccm.so*' \
            -o -name 'libxcb-ewmh.so*' \) -print0)
    ((${#keep[@]} > 0)) || die "runtime libraries are missing for xcb-util-wm"
    package_keep "${keep[@]}"
}

recipe_main "$@"
