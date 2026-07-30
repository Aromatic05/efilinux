#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=noto-sans-cjk-sc
pkgver=2.004
sysroot=false

depends=()
builddepends=()
makedepends=(install)

prepare() {
    local font="$downloaddir/NotoSansCJKsc-Regular-$pkgver.otf"
    download "https://raw.githubusercontent.com/notofonts/noto-cjk/Sans$pkgver/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf" "$font"
    checksum sha256 2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b "$font"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] || cp "$font" "$srcdir/NotoSansCJKsc-Regular.otf"
}

build() {
    install -Dm0644 "$srcdir/NotoSansCJKsc-Regular.otf" "$develdir/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf"
}

package() { :; }

recipe_main "$@"
