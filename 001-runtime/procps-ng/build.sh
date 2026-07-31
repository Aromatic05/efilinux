#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=procps-ng
pkgver=4.0.6
depends=(glibc ncurses)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/procps-ng-$pkgver.tar.xz"
    download "https://downloads.sourceforge.net/project/procps-ng/Production/procps-ng-$pkgver.tar.xz" "$archive"
    checksum sha256 67bea6fbc3a42a535a0230c9e891e5ddfb4d9d39422d46565a2990d1ace15216 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin --sbindir=/usr/bin \
        --libdir=/usr/lib --disable-static --disable-nls --disable-kill \
        --disable-w --disable-numa --disable-whining --enable-watch8bit \
        --without-systemd --without-elogind
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() {
    rm -rf "$develdir/usr/share" "$develdir/usr/include"
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}
package() {
    local -a keep=(
        /usr/bin/free /usr/bin/pgrep /usr/bin/pkill /usr/bin/pmap
        /usr/bin/ps /usr/bin/pwdx /usr/bin/slabtop /usr/bin/sysctl /usr/bin/tload
        /usr/bin/top /usr/bin/uptime /usr/bin/vmstat /usr/bin/watch
    )
    package_add_library_family keep 'libproc2.so.1*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
