#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=dejavu-fonts
pkgver=2.37

depends=()
builddepends=()
makedepends=(find install)

prepare() {
    local archive="$downloaddir/dejavu-fonts-ttf-2.37.tar.bz2"

    download \
        "https://downloads.sourceforge.net/dejavu/dejavu-fonts-ttf-2.37.tar.bz2" \
        "$archive"
    checksum \
        sha256 \
        fa9ca4d13871dd122f61258a80d01751d603b4d3ee14095d65453b4e846e17d7 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    install -d -m0755 "$develdir/usr/share/fonts/truetype/dejavu"
    find "$srcdir/source/ttf" -maxdepth 1 -type f -name '*.ttf'             -exec install -m0644 -t "$develdir/usr/share/fonts/truetype/dejavu" {} +
}

package() {
    :
}

recipe_main "$@"
