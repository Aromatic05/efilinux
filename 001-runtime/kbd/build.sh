#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=kbd
pkgver=2.10.0

depends=(
    glibc
    xz
    zlib
    zstd
)
builddepends=(
    linux-headers
)
makedepends=(
    autoreconf
    gcc
    make
    patch
    python3
)

prepare() {
    local archive="$downloaddir/kbd-$pkgver.tar.xz"
    local patch_file="$downloaddir/kbd-$pkgver-backspace-1.patch"

    download \
        "https://www.kernel.org/pub/linux/utils/kbd/kbd-$pkgver.tar.xz" \
        "$archive"
    download \
        "https://www.linuxfromscratch.org/patches/lfs/development/kbd-$pkgver-backspace-1.patch" \
        "$patch_file"
    checksum \
        sha256 \
        6e5ca4f8d76ee9e3a8db700b667f13e12aac9933828a64e1aaad93d26be9b479 \
        "$archive"
    checksum \
        sha256 \
        8be28dcb11420624a500f2ea4fe975f771174bffee50e54ec8cd295a2dec104e \
        "$patch_file"
    extract "$archive" "$srcdir/kbd"
}

build() {
    local patch_file="$downloaddir/kbd-$pkgver-backspace-1.patch"

    patch -d "$srcdir/kbd" -Np1 < "$patch_file"
    python3 - "$srcdir/kbd/configure.ac" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'AS_IF([test "$HAVE_BZIP2" = "no"], [\n\tAC_CHECK_LIB(bz2, BZ2_bzDecompressInit, ['
new = 'AS_IF([test "$with_bzip2" != "no" && test "$HAVE_BZIP2" = "no"], [\n\tAC_CHECK_LIB(bz2, BZ2_bzDecompressInit, ['
if source.count(old) != 1:
    raise SystemExit("unexpected Kbd bzip2 fallback structure")
path.write_text(source.replace(old, new))
PY
    autoreconf -fi "$srcdir/kbd"

    log "Configuring Kbd"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/kbd/configure" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --disable-vlock \
            --disable-nls \
            --disable-tests \
            --disable-xkb \
            --with-zlib \
            --without-bzip2 \
            --with-lzma \
            --with-zstd

    log "Building Kbd"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/share/keymaps" -type f -name '*.orig' -delete
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/deallocvt \
        /usr/bin/dumpkeys \
        /usr/bin/kbd_mode \
        /usr/bin/loadkeys \
        /usr/bin/setfont \
        /usr/bin/showkey \
        /usr/share/keymaps/ \
        /usr/share/consolefonts/ \
        /usr/share/consoletrans/ \
        /usr/share/unimaps/
}

recipe_main "$@"
