#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=spice-protocol
pkgver=0.14.5
depends=()
builddepends=()
makedepends=(meson ninja python3)
prepare() {
    local archive="$downloaddir/spice-protocol-$pkgver.tar.xz"
    download "https://www.spice-space.org/download/releases/spice-protocol-$pkgver.tar.xz" "$archive"
    checksum sha256 baf58449f6e89d19f475899ad5fb9196fdc46c03cc53233f4e39cf2978f9cff7 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir"
    target_meson_install "$builddir" "$develdir"
    install -Dm0644 /dev/null "$develdir/usr/share/efilinux/build-components/spice-protocol.stamp"
}
package() { package_keep /usr/share/efilinux/build-components/spice-protocol.stamp; }
recipe_main "$@"
