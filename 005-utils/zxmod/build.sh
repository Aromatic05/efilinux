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

depends=(doas kmod shared-mime-info squashfs-tools util-linux)
builddepends=()
makedepends=(install)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    install -Dm0755 "$srcdir/files/usr/bin/zxmod" "$develdir/usr/bin/zxmod"
    install -Dm0755 "$srcdir/files/usr/bin/zxmod-build" "$develdir/usr/bin/zxmod-build"
    install -Dm0755 "$srcdir/files/usr/bin/zxmod-open" "$develdir/usr/bin/zxmod-open"
    install -Dm0644 "$srcdir/files/usr/lib/zxmod/common.sh" \
        "$develdir/usr/lib/zxmod/common.sh"
    install -Dm0644 "$srcdir/files/usr/share/applications/zxmod-load.desktop" \
        "$develdir/usr/share/applications/zxmod-load.desktop"
    install -Dm0644 "$srcdir/files/usr/share/mime/packages/application-vnd.efilinux.zxm.xml" \
        "$develdir/usr/share/mime/packages/application-vnd.efilinux.zxm.xml"
    install -Dm0644 "$srcdir/files/etc/xdg/mimeapps.list" \
        "$develdir/etc/xdg/mimeapps.list"
    install -d -m0755 "$develdir/opt"
}

package() {
    :
}

recipe_main "$@"
