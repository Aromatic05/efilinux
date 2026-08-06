#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=fio
pkgver=3.42
depends=(glibc glibc-libmvec libaio zlib)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/fio-$pkgver.tar.gz"
    download "https://github.com/axboe/fio/archive/refs/tags/fio-$pkgver.tar.gz" "$archive"
    checksum sha256 56b03497a918d07692257890fd759bf73168ad79df5be78a2bcbbdc8ce67895b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    cp -a "$srcdir/source/." "$builddir/"
    (
        cd "$builddir"
        CC="$(target_compiler_wrapper gcc)" \
        CFLAGS="$CFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            ./configure \
                --prefix=/usr \
                --disable-dfs \
                --disable-gfapi \
                --disable-http \
                --disable-isal \
                --disable-isal64 \
                --disable-libblkio \
                --disable-libnfs \
                --disable-libzbc \
                --disable-native \
                --disable-numa \
                --disable-pmem \
                --disable-rados \
                --disable-rbd \
                --disable-rdma \
                --disable-shm \
                --disable-tcmalloc \
                --disable-xnvme
        make -j"$EFILINUX_JOBS"
    )
    install -Dm0755 "$builddir/fio" "$develdir/usr/bin/fio"
}
check() { [[ -x "$develdir/usr/bin/fio" ]] || die "fio binary is missing"; }
devel() { strip_all "$develdir/usr/bin/fio"; }
package() { package_keep /usr/bin/fio; }
recipe_main "$@"
