#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xfce4-taskmanager
pkgver=1.5.8
depends=(glib glibc gtk3 xfce)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/xfce4-taskmanager-$pkgver.tar.bz2"
    download "https://archive.xfce.org/src/apps/xfce4-taskmanager/1.5/xfce4-taskmanager-$pkgver.tar.bz2" "$archive"
    checksum sha256 14b9d68b8feb88a642a9885b8549efe7fc9e6c155f638003f2a4a58d9eb2baab "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-debug
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin"; }

package() {
    package_keep /usr/bin/xfce4-taskmanager /usr/share/applications/ /usr/share/icons/hicolor/
}

recipe_main "$@"
