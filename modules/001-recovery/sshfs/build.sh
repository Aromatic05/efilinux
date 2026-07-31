#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=sshfs
pkgver=3.7.6
depends=(fuse glib glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/sshfs-$pkgver.tar.gz"
    download "https://github.com/libfuse/sshfs/archive/refs/tags/sshfs-$pkgver.tar.gz" "$archive"
    checksum sha256 67a3e166a39b07708497ee0aee308547dba386053cf8d816b4ce8a9b3066a6ce "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --sbindir=bin \
        -Dstrip=false
    target_meson_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/sshfs \
        /usr/bin/mount.sshfs \
        /usr/bin/mount.fuse.sshfs
}

recipe_main "$@"
