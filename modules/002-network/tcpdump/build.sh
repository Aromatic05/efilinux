#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=tcpdump
pkgver=4.99.6
depends=(glibc libpcap openssl)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/tcpdump-$pkgver.tar.xz"
    download "https://www.tcpdump.org/release/tcpdump-$pkgver.tar.xz" "$archive"
    checksum sha256 40a8cefd45f0d2a06827e6658efb830d484868c449ad80f7efb33516af44f3da "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --without-smi \
        --with-crypto="$EFILINUX_SYSROOT/usr"
    target_make_install "$builddir" "$develdir"
}

devel() {
    chmod 0755 "$develdir/usr/bin/tcpdump"
    rm -rf "$develdir/usr/share/man"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/tcpdump
}

recipe_main "$@"
