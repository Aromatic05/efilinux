#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=efilinux-console-config
pkgver=1
sysroot=false

depends=(efilinux-system-config)
builddepends=()
makedepends=(install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    install -Dm0644 "$srcdir/files/etc/inittab" "$develdir/etc/inittab"
}

package() { :; }

recipe_main "$@"
