#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=slang
pkgver=2.3.3
depends=(glibc ncurses)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/slang-$pkgver.tar.bz2"
    download "https://www.jedsoft.org/releases/slang/slang-$pkgver.tar.bz2" "$archive"
    checksum sha256 f9145054ae131973c61208ea82486d5dd10e3c5cdad23b7c4a0617743c8f5a18 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    cp -a "$srcdir/source/." "$builddir/"
    (
        cd "$builddir"
        CC="$(target_compiler_wrapper gcc)" \
        AR=ar \
        RANLIB=ranlib \
        CFLAGS="$CFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
            ./configure \
                --prefix=/usr \
                --libdir=/usr/lib \
                --with-terminfo=default \
                --without-onig \
                --without-pcre \
                --without-png
    )
    make -C "$builddir/src" -j"$EFILINUX_JOBS" elf
    make -C "$builddir/src" DESTDIR="$develdir" install-elf
    install -d -m0755 "$develdir/usr/lib/pkgconfig"
    cat > "$develdir/usr/lib/pkgconfig/slang.pc" <<EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: S-Lang
Description: S-Lang programming library
Version: $pkgver
Libs: -L\${libdir} -lslang
Libs.private: -ldl -lm
Cflags: -I\${includedir}
EOF
}
check() { [[ -f "$develdir/usr/lib/libslang.so.2" ]] || die "S-Lang shared library is missing"; }
devel() { strip_all "$develdir/usr/lib"; }
package() {
    local -a keep=()
    package_add_library_family keep 'libslang.so.2*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
