#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=efilinux-xfce-config
pkgver=1
sysroot=false

depends=()
builddepends=()
makedepends=(install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    cp -a "$srcdir/files/." "$develdir/"
    chmod 0755 "$develdir/usr/bin/efilinux-audio-session"
}

package() {
    :
}

recipe_main "$@"
