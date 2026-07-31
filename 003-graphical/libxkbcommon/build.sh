#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libxkbcommon
pkgver=1.13.2

depends=(glibc xkeyboard-config xorg)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libxkbcommon-$pkgver.tar.gz"
    download "https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-$pkgver.tar.gz" "$archive"
    checksum sha256 acc4d5f7c3cbba5f9f8d08d8bdbeede84ecede46792f47929aa9321873385528 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Denable-tools=false \
        -Denable-x11=true \
        -Denable-docs=false \
        -Denable-wayland=false \
        -Denable-xkbregistry=false \
        -Denable-bash-completion=false \
        -Ddefault-rules=evdev \
        -Ddefault-model=pc105 \
        -Ddefault-layout=us
    target_meson_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libxkbcommon.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
