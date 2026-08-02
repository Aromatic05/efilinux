#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=efilinux-live
pkgver=1
sysroot=false

depends=(
    bash
    busybox
    coreutils
    e2fsprogs
    findutils
    gawk
    grep
    kmod
    udev
    util-linux
)
builddepends=()
makedepends=(install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    cp -a "$srcdir/files/." "$develdir/"
    chmod 0755 \
        "$develdir/usr/bin/efilinux-livectl" \
        "$develdir/usr/bin/efilinux-persistence-create" \
        "$develdir/usr/libexec/efilinux-live-root" \
        "$develdir/usr/libexec/efilinux-live-modules"
    chmod 0644 "$develdir/usr/lib/efilinux/live-common.sh"
}

package() {
    :
}

recipe_main "$@"
