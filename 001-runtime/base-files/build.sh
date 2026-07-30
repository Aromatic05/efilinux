#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=base-files
pkgver=1
sysroot=false

depends=(kmod)
builddepends=()
makedepends=(install mknod)

prepare() {
    :
}

build() {
    install -d -m0755 \
        "$develdir/dev" \
        "$develdir/etc" \
        "$develdir/proc" \
        "$develdir/root" \
        "$develdir/run" \
        "$develdir/sys" \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
    install -d -m1777 "$develdir/tmp"

    ln -s usr/bin "$develdir/bin"
    ln -s usr/bin "$develdir/sbin"
    ln -s usr/lib "$develdir/lib"
    ln -s usr/lib "$develdir/lib64"
    ln -s bin "$develdir/usr/sbin"

    mknod -m0600 "$develdir/dev/console" c 5 1
    mknod -m0666 "$develdir/dev/null" c 1 3

    cat > "$develdir/etc/mdev.conf" <<'MDEV'
$MODALIAS=.* 0:0 660 @/usr/bin/modprobe "$MODALIAS"
MDEV
    chmod 0644 "$develdir/etc/mdev.conf"
}

package() {
    :
}

recipe_main "$@"
