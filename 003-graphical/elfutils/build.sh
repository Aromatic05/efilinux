#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=elfutils
pkgver=0.195

depends=(glibc zlib zstd)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/elfutils-0.195.tar.bz2"

    download \
        "https://sourceware.org/elfutils/ftp/0.195/elfutils-0.195.tar.bz2" \
        "$archive"
    checksum \
        sha256 \
        37629fdf7f1f3dc2818e138fca2b8094177d6c2d0f701d3bb650a561218dc026 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir"             --disable-debuginfod             --disable-libdebuginfod             --disable-nls             --disable-demangler             --without-bzlib             --without-lzma             --with-zstd
    target_make_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libasm.so.1*'
    package_add_library_family keep 'libdw.so.1*'
    package_add_library_family keep 'libelf.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
