#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=recovery-launchers
pkgver=1
depends=(clonezilla testdisk)
builddepends=()
makedepends=(install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    install -d -m0755 \
        "$develdir/usr/bin" \
        "$develdir/usr/share/applications"
    install -m0755 "$srcdir/files/usr/bin/"* "$develdir/usr/bin/"
    install -m0644 "$srcdir/files/usr/share/applications/"*.desktop \
        "$develdir/usr/share/applications/"
}

package() {
    package_keep \
        /usr/bin/recovery-clonezilla \
        /usr/bin/recovery-testdisk \
        /usr/bin/recovery-photorec \
        /usr/share/applications/recovery-clonezilla.desktop \
        /usr/share/applications/recovery-testdisk.desktop \
        /usr/share/applications/recovery-photorec.desktop
}

recipe_main "$@"
