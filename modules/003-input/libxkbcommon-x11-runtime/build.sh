#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libxkbcommon-x11-runtime
pkgver=1.13.2
depends=(glibc libxkbcommon xorg)
builddepends=(libxkbcommon)
makedepends=(install)

prepare() { :; }

build() {
    local source_lib="$EFILINUX_SYSROOT/usr/lib"
    local target_lib="$develdir/opt/fcitx5/lib"
    local path

    install -d -m0755 "$target_lib"
    while IFS= read -r -d '' path; do
        cp -a "$path" "$target_lib/"
    done < <(find "$source_lib" -maxdepth 1 \
        \( -type f -o -type l \) -name 'libxkbcommon-x11.so*' -print0)

    [[ -e "$target_lib/libxkbcommon-x11.so.0" ]] || \
        die 'libxkbcommon-x11 runtime library was not found in the target sysroot'
}

package() {
    package_keep /opt/fcitx5/lib/
}

recipe_main "$@"
