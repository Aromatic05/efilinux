#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=runtime-init
pkgver=1
sysroot=false

depends=(busybox)
builddepends=()
makedepends=(install)

prepare() {
    :
}

build() {
    install -d -m0755 "$develdir/usr/bin"
    ln -s /usr/bin/init "$develdir/init"
    ln -s busybox "$develdir/usr/bin/init"
}

package() {
    :
}

recipe_main "$@"
