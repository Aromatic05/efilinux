#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=tar
pkgver=1.35
depends=(acl attr glibc)
builddepends=()
makedepends=(gcc make patch)
prepare() {
    local archive="$downloaddir/tar-$pkgver.tar.xz"
    local patch_file="$downloaddir/tar-$pkgver-acl_fix-1.patch"
    download "https://ftp.gnu.org/gnu/tar/tar-$pkgver.tar.xz" "$archive"
    checksum sha256 4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16 "$archive"
    download "https://www.linuxfromscratch.org/patches/lfs/development/tar-$pkgver-acl_fix-1.patch" "$patch_file"
    checksum sha256 51cadccfcb2f29cfdb4ec18015360100aa167179a72ece040a6a8612aeec5081 "$patch_file"
    extract "$archive" "$srcdir/source"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$patch_file"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" FORCE_UNSAFE_CONFIGURE=1 \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-nls --disable-dependency-tracking --without-selinux
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() { rm -rf "$develdir/usr/share"; strip_all "$develdir/usr/bin/tar"; }
package() { package_keep /usr/bin/tar; }
recipe_main "$@"
