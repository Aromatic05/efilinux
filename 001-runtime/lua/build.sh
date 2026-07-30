#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=lua
pkgver=5.4.8

depends=(glibc)
builddepends=()
makedepends=(gcc install pkg-config)

prepare() {
    local archive="$downloaddir/lua-$pkgver.tar.gz"
    download "https://www.lua.org/ftp/lua-$pkgver.tar.gz" "$archive"
    checksum sha256 4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae "$archive"
    extract "$archive" "$srcdir/lua"
}

build() {
    local source_file object
    local -a lua_sources=()

    mkdir -p "$builddir/objects" "$develdir/usr/lib/pkgconfig" \
        "$develdir/usr/include" "$develdir/usr/bin"
    mapfile -t lua_sources < <(
        find "$srcdir/lua/src" -maxdepth 1 -type f -name '*.c' \
            ! -name lua.c ! -name luac.c -print | LC_ALL=C sort
    )
    for source_file in "${lua_sources[@]}"; do
        object="$builddir/objects/$(basename "${source_file%.c}").o"
        "$CC" $CFLAGS -fPIC -DLUA_USE_LINUX \
            -I"$srcdir/lua/src" -c "$source_file" -o "$object"
    done
    "$CC" $LDFLAGS -shared -Wl,-soname,liblua.so.5.4 \
        -o "$develdir/usr/lib/liblua.so.$pkgver" \
        "$builddir"/objects/*.o -ldl -lm
    ln -s "liblua.so.$pkgver" "$develdir/usr/lib/liblua.so.5.4"
    ln -s liblua.so.5.4 "$develdir/usr/lib/liblua.so"
    install -m0644 "$srcdir/lua"/src/{lua.h,lauxlib.h,lualib.h,luaconf.h} \
        "$develdir/usr/include/"
    cat > "$develdir/usr/lib/pkgconfig/lua.pc" <<PC
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: Lua
Description: Lua language engine
Version: $pkgver
Libs: -L\${libdir} -llua -lm -ldl
Cflags: -I\${includedir}
PC
}

devel() {
    strip_all "$develdir/usr/lib/liblua.so.$pkgver"
}

package() {
    local -a keep=()
    package_add_library_family keep 'liblua.so.5.4*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
