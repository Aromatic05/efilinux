#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=coreutils
pkgver=9.11
depends=(acl attr glibc gmp)
builddepends=()
makedepends=(gcc make perl)
prepare() {
    local archive="$downloaddir/coreutils-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/coreutils/coreutils-$pkgver.tar.xz" "$archive"
    checksum sha256 394024eda0a5955217ceda9cd1201e65dc8fa3aa29c2951135a49521d57c3cc3 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" FORCE_UNSAFE_CONFIGURE=1 \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-nls --disable-dependency-tracking --disable-libcap \
        --without-openssl --without-selinux
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() {
    rm -rf "$develdir/usr/share"
    strip_all "$develdir/usr/bin" "$develdir/usr/libexec"
}
package() {
    local -a keep=(
        /usr/bin/[ /usr/bin/basename /usr/bin/cat /usr/bin/chgrp /usr/bin/chmod
        /usr/bin/chown /usr/bin/cksum /usr/bin/comm /usr/bin/cp /usr/bin/cut
        /usr/bin/date /usr/bin/dd /usr/bin/df /usr/bin/dirname /usr/bin/du
        /usr/bin/echo /usr/bin/env /usr/bin/expand /usr/bin/expr /usr/bin/false
        /usr/bin/fmt /usr/bin/fold /usr/bin/groups /usr/bin/head /usr/bin/id
        /usr/bin/install /usr/bin/join /usr/bin/link /usr/bin/ln /usr/bin/ls
        /usr/bin/mkdir /usr/bin/mkfifo /usr/bin/mknod /usr/bin/mktemp /usr/bin/mv
        /usr/bin/nice /usr/bin/nohup /usr/bin/nproc /usr/bin/od /usr/bin/paste
        /usr/bin/printenv /usr/bin/printf /usr/bin/pwd /usr/bin/readlink
        /usr/bin/realpath /usr/bin/rm /usr/bin/rmdir /usr/bin/seq /usr/bin/sha256sum
        /usr/bin/sleep /usr/bin/sort /usr/bin/split /usr/bin/stat /usr/bin/stdbuf
        /usr/bin/stty /usr/bin/sync /usr/bin/tac /usr/bin/tail /usr/bin/tee
        /usr/bin/test /usr/bin/timeout /usr/bin/touch /usr/bin/tr /usr/bin/true
        /usr/bin/truncate /usr/bin/tty /usr/bin/uname /usr/bin/unexpand
        /usr/bin/uniq /usr/bin/unlink /usr/bin/wc /usr/bin/whoami /usr/bin/yes
        /usr/libexec/coreutils/libstdbuf.so
    )
    package_keep "${keep[@]}"
}
recipe_main "$@"
