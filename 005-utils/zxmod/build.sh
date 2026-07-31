#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=zxmod
pkgver=1
sysroot=false

depends=(kmod openssl squashfs-tools util-linux)
builddepends=()
makedepends=(install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    install -Dm0755 "$srcdir/files/usr/bin/zxmod" "$develdir/usr/bin/zxmod"
    install -Dm0755 "$srcdir/files/usr/bin/zxmod-build" "$develdir/usr/bin/zxmod-build"
    install -Dm0644 "$srcdir/files/usr/lib/zxmod/common.sh" \
        "$develdir/usr/lib/zxmod/common.sh"
    install -Dm0755 "$srcdir/files/etc/rc.d/init.d/zxmod" \
        "$develdir/etc/rc.d/init.d/zxmod"
    for runlevel in 2 3 4 5; do
        install -d -m0755 "$develdir/etc/rc.d/rc${runlevel}.d"
        ln -s ../init.d/zxmod "$develdir/etc/rc.d/rc${runlevel}.d/S65zxmod"
    done
    install -d -m0755 "$develdir/opt"
}

package() {
    :
}

recipe_main "$@"
