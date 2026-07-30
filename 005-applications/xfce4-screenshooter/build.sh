#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xfce4-screenshooter
pkgver=1.10.6
depends=(glib glibc gtk3 libpng xfce xorg)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/xfce4-screenshooter-$pkgver.tar.bz2"
    download "https://archive.xfce.org/src/apps/xfce4-screenshooter/1.10/xfce4-screenshooter-$pkgver.tar.bz2" "$archive"
    checksum sha256 992066cfecfb44a68681340bfd55d524d40410aac3da6ef25c6c6cb2150a5965 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-debug
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }

package() {
    local -a keep=(/usr/bin/xfce4-screenshooter /usr/share/applications/ /usr/share/icons/hicolor/)
    [[ ! -d "$pkgdir/usr/lib/xfce4/panel/plugins" ]] || keep+=(/usr/lib/xfce4/panel/plugins/)
    [[ ! -d "$pkgdir/usr/share/xfce4/panel/plugins" ]] || keep+=(/usr/share/xfce4/panel/plugins/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
