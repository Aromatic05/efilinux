#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=gsmartcontrol
pkgver=2.0.2
depends=(gcc-libs glibc glibmm gtkmm smartmontools)
builddepends=()
makedepends=(cmake g++ ninja pkg-config)
prepare() {
    local archive="$downloaddir/gsmartcontrol-$pkgver.tar.gz"
    download "https://github.com/ashaduri/gsmartcontrol/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 7cebd83fd34883d51e143389aa88f8173ea7b67c760b12b7de847f3c3c8cee34 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DCMAKE_INSTALL_PREFIX=/opt/recovery \
        -DAPP_BUILD_EXAMPLES=OFF \
        -DAPP_BUILD_TESTS=OFF \
        -DCMAKE_INSTALL_SBINDIR=bin
    target_cmake_install "$builddir" "$develdir"
    rm -f \
        "$develdir/opt/recovery/bin/gsmartcontrol-root" \
        "$develdir/opt/recovery/share/applications/gsmartcontrol.desktop" \
        "$develdir/opt/recovery/share/polkit-1/actions/org.gsmartcontrol.policy" \
        "$develdir/opt/recovery/share/metainfo/gsmartcontrol.appdata.xml"
}
check() { [[ -x "$develdir/opt/recovery/bin/gsmartcontrol" ]] || die "gsmartcontrol binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/gsmartcontrol"; }
package() {
    package_keep \
        /opt/recovery/bin/gsmartcontrol \
        /opt/recovery/share/gsmartcontrol/
}
recipe_main "$@"
