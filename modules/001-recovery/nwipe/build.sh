#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=nwipe
pkgver=0.42
depends=(dmidecode glibc hdparm libconfig ncurses ncurses-panelw parted)
builddepends=()
makedepends=(autoconf automake gcc make pkg-config)
prepare() {
    local archive="$downloaddir/nwipe-$pkgver.tar.gz"
    download "https://github.com/martijnvanbrummelen/nwipe/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 0e38474495cc6c86043a1de0460cf0dc009ad68e079ee23d71569e80e55cd2e6 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_autotools_configure "$srcdir/source" "$builddir" \
        --prefix=/opt/recovery \
        --libdir=/opt/recovery/lib
    target_make_install "$builddir" "$develdir"
}
check() { [[ -x "$develdir/opt/recovery/bin/nwipe" || -x "$develdir/opt/recovery/sbin/nwipe" ]] || die "nwipe binary is missing"; }
devel() {
    if [[ -x "$develdir/opt/recovery/sbin/nwipe" ]]; then
        install -Dm0755 "$develdir/opt/recovery/sbin/nwipe" "$develdir/opt/recovery/bin/nwipe"
        rm -f "$develdir/opt/recovery/sbin/nwipe"
    fi
    strip_all "$develdir/opt/recovery/bin/nwipe"
}
package() { package_keep /opt/recovery/bin/nwipe; }
recipe_main "$@"
