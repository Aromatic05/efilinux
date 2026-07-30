#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xkeyboard-config
pkgver=2.48

depends=()
builddepends=()
makedepends=(gcc meson ninja python3)

prepare() {
    local archive="$downloaddir/xkeyboard-config-2.48.tar.gz"

    download \
        "https://gitlab.freedesktop.org/xkeyboard-config/xkeyboard-config/-/archive/xkeyboard-config-2.48/xkeyboard-config-xkeyboard-config-2.48.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        1e304d3c7a74bfbad0bae16b25d4c2b2eda06714b988953607a06cc013bf3077 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    sed -i \
        "s/find_program('xsltproc', required: false)/find_program('efilinux-disabled-xsltproc', required: false)/" \
        "$srcdir/source/meson.build"
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dcompat-rules=true \
        -Dxorg-rules-symlinks=true \
        -Dnls=false \
        -Dnon-latin-layouts-list=false
    target_meson_install "$builddir" "$develdir"
}

package() {
    rm -rf "$pkgdir/usr/share/pkgconfig"
}

recipe_main "$@"
