#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=smartmontools
pkgver=7.5
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/smartmontools-$pkgver.tar.gz"
    download "https://downloads.sourceforge.net/project/smartmontools/smartmontools/$pkgver/smartmontools-$pkgver.tar.gz" "$archive"
    checksum sha256 690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --sbindir=/usr/bin \
        --disable-dependency-tracking \
        --with-initscriptdir=no \
        --with-smartdplugindir=no \
        --with-libcap-ng=no \
        --with-libsystemd=no \
        --with-selinux=no \
        --with-drivedbinstdir=/usr/share/smartmontools \
        --with-drivedbdir=/usr/share/smartmontools \
        --with-update-smart-drivedb=no \
        --with-gnupg=no \
        --with-nvme-devicescan=yes
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin"; }
package() {
    local -a keep=(/usr/bin/smartctl)
    [[ ! -f "$pkgdir/usr/share/smartmontools/drivedb.h" ]] || keep+=(/usr/share/smartmontools/drivedb.h)
    package_keep "${keep[@]}"
}
recipe_main "$@"
