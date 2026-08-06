#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
source "$ROOT/modules/001-recovery/lib/target-layout.sh"
pkgname=gigolo
pkgver=0.6.0
depends=(glib glibc gtk3 gvfs)
builddepends=()
makedepends=(gcc meson ninja pkg-config)
prepare() {
    local archive="$downloaddir/gigolo-$pkgver.tar.xz"
    download "https://archive.xfce.org/src/apps/gigolo/0.6/gigolo-$pkgver.tar.xz" "$archive"
    checksum sha256 f27dbb51abe8144c1b981f2d820ad1b279c1bc4623d7333b7d4f5f4777eb45ed "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    input_shared_file "$ROOT/modules/001-recovery/lib/target-layout.sh" "$srcdir/recovery-target-layout.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" --prefix=/opt/recovery
    target_meson_install "$builddir" "$develdir"
    recovery_prune_translations "$develdir"
    sed -i \
        -e 's#^Exec=.*#Exec=/opt/recovery/bin/gigolo#' \
        -e 's#^Icon=.*#Icon=network-server#' \
        "$develdir/opt/recovery/share/applications/gigolo.desktop"
    recovery_publish_usr_paths "$develdir" \
        share/applications
}
check() { [[ -x "$develdir/opt/recovery/bin/gigolo" ]] || die "gigolo binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/gigolo"; }
package() {
    package_keep \
        /opt/recovery/bin/gigolo \
        /usr/share/applications/gigolo.desktop \
        /opt/recovery/share/locale/
}
recipe_main "$@"
