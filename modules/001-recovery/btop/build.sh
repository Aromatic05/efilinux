#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
source "$ROOT/modules/001-recovery/lib/target-layout.sh"
pkgname=btop
pkgver=1.4.7
depends=(gcc-libs glibc)
builddepends=()
makedepends=(cmake g++ ninja)
prepare() {
    local archive="$downloaddir/btop-$pkgver.tar.gz"
    download "https://github.com/aristocratos/btop/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 933de2e4d1b2211a638be463eb6e8616891bfba73aef5d38060bd8319baeefc6 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    input_shared_file "$ROOT/modules/001-recovery/lib/target-layout.sh" "$srcdir/recovery-target-layout.sh"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_INSTALL_PREFIX=/opt/recovery \
        -DBTOP_GPU=OFF \
        -DBTOP_LTO=OFF \
        -DBTOP_STATIC=OFF
    target_cmake_install "$builddir" "$develdir"
    sed -i \
        -e 's#^Exec=.*#Exec=/opt/recovery/bin/btop#' \
        -e 's#^Icon=.*#Icon=utilities-system-monitor#' \
        "$develdir/opt/recovery/share/applications/btop.desktop"
    recovery_publish_usr_paths "$develdir" \
        share/applications
}
check() { [[ -x "$develdir/opt/recovery/bin/btop" ]] || die "btop binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/btop"; }
package() {
    package_keep \
        /opt/recovery/bin/btop \
        /usr/share/applications/btop.desktop \
        /opt/recovery/share/btop/
}
recipe_main "$@"
