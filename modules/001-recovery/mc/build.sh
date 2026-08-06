#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=mc
pkgver=4.8.33
depends=(e2fsprogs glib glibc ncurses)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/mc-$pkgver.tar.xz"
    download "https://ftp.osuosl.org/pub/midnightcommander/mc-$pkgver.tar.xz" "$archive"
    checksum sha256 cae149d42f844e5185d8c81d7db3913a8fa214c65f852200a9d896b468af164c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --prefix=/opt/recovery \
        --libdir=/opt/recovery/lib \
        --disable-nls \
        --disable-tests \
        --disable-vfs-extfs \
        --disable-vfs-ftp \
        --disable-vfs-sftp \
        --disable-vfs-sfs \
        --disable-vfs-shell \
        --disable-vfs-undelfs \
        --with-screen=ncurses \
        --without-gpm-mouse \
        --without-x
    target_make_install "$builddir" "$develdir"
}
check() { [[ -x "$develdir/opt/recovery/bin/mc" ]] || die "Midnight Commander binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin" "$develdir/opt/recovery/libexec/mc"; }
package() {
    package_keep \
        /opt/recovery/bin/mc \
        /opt/recovery/bin/mcdiff \
        /opt/recovery/bin/mcedit \
        /opt/recovery/bin/mcview \
        /opt/recovery/libexec/mc/ \
        /opt/recovery/share/mc/
}
recipe_main "$@"
