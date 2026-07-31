#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=partclone
pkgver=0.3.47
depends=(btrfs-progs e2fsprogs fuse glibc ncurses ntfs-3g openssl userspace-rcu util-linux xfsprogs zlib zstd)
builddepends=()
makedepends=(autoconf automake gcc make pkg-config)
prepare() {
    local archive="$downloaddir/partclone-$pkgver.tar.gz"
    download "https://github.com/Thomas-Tsai/partclone/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 8215844d14737d8fbb09fe1b1eafe688a8c790eafc8413a26c08e5795ac9ccd3 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    (cd "$srcdir/source" && autoreconf -fi)
}
build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --sbindir=/usr/bin \
        --disable-static-linking \
        --disable-isal \
        --disable-xxhash \
        --enable-fuse \
        --enable-extfs \
        --enable-xfs \
        --disable-reiserfs \
        --disable-reiser4 \
        --disable-hfsp \
        --disable-apfs \
        --enable-fat \
        --enable-exfat \
        --disable-f2fs \
        --disable-nilfs2 \
        --enable-ntfs \
        --disable-ufs \
        --disable-vmfs \
        --disable-jfs \
        --enable-btrfs \
        --enable-minix \
        --enable-ncursesw \
        --disable-mtrace \
        --disable-fs-test
    target_make_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin"; }
package() {
    local -a keep=()
    local command
    for command in "$pkgdir"/usr/bin/partclone.*; do
        [[ -f "$command" && -x "$command" ]] || continue
        keep+=("/${command#"$pkgdir/"}")
    done
    ((${#keep[@]} > 0)) || die 'partclone installed no runtime commands'
    package_keep "${keep[@]}"
}
recipe_main "$@"
