#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/desktop-libraries/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command autoreconf curl gcc make meson ninja pkg-config sha256sum tar unzip
ensure_directories

recipe_inputs=("$ROOT/001-runtime/desktop-libraries/config.sh")

restore_package() {
    binary_package_restore_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

publish_package() {
    binary_package_publish_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

prepare_tar_package() {
    local package=$1 archive_name=$2 digest=$3 url=$4
    local archive="$EFILINUX_DOWNLOADS/$archive_name"

    prepare_package "$package"
    download "$url" "$archive"
    verify_sha256 "$digest" "$archive"
    extract_source "$archive" "$PACKAGE_SOURCE"
}

configure_target() {
    local source=$1
    shift
    (
        cd "$PACKAGE_BUILD"
        CC=gcc \
        CFLAGS="$(target_cflags)" \
        CPPFLAGS="--sysroot=$EFILINUX_SYSROOT" \
        LDFLAGS="$(target_ldflags)" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$source/configure" \
                --prefix=/usr \
                --libdir=/usr/lib \
                --sysconfdir=/etc \
                "$@"
    )
}

make_target() {
    make -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
}

meson_target() {
    local source=$1
    shift
    CC=gcc \
    CFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$source" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            "$@"
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" \
        meson install -C "$PACKAGE_BUILD"
}

package="ncurses-$NCURSES_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "ncurses-$NCURSES_VERSION.tar.gz" \
        "$NCURSES_SHA256" \
        "https://ftp.gnu.org/gnu/ncurses/$package.tar.gz"
    configure_target "$PACKAGE_SOURCE" \
        --with-shared \
        --without-normal \
        --without-debug \
        --enable-widec \
        --enable-pc-files \
        --with-pkg-config-libdir=/usr/lib/pkgconfig \
        --without-ada \
        --without-cxx-binding \
        --without-tests
    make_target
    for library in ncurses form panel menu; do
        printf 'INPUT(-l%sw)\n' "$library" > "$PACKAGE_STAGING/usr/lib/lib$library.so"
        ln -sf "${library}w.pc" "$PACKAGE_STAGING/usr/lib/pkgconfig/$library.pc"
    done
    ln -sf libncurses.so "$PACKAGE_STAGING/usr/lib/libcurses.so"
    publish_package "$package"
fi

package="readline-$READLINE_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$READLINE_SHA256" \
        "https://ftp.gnu.org/gnu/readline/$package.tar.gz"
    configure_target "$PACKAGE_SOURCE" --disable-static
    make -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS" SHLIB_LIBS=-lncursesw
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" SHLIB_LIBS=-lncursesw install
    publish_package "$package"
fi

package="lua-$LUA_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$LUA_SHA256" \
        "https://www.lua.org/ftp/$package.tar.gz"
    mkdir -p "$PACKAGE_BUILD/objects" "$PACKAGE_STAGING/usr/lib/pkgconfig" \
        "$PACKAGE_STAGING/usr/include" "$PACKAGE_STAGING/usr/bin"
    mapfile -t lua_sources < <(
        find "$PACKAGE_SOURCE"/src -maxdepth 1 -type f -name '*.c' \
            ! -name lua.c ! -name luac.c -print | sort
    )
    for source_file in "${lua_sources[@]}"; do
        object="$PACKAGE_BUILD/objects/$(basename "${source_file%.c}").o"
        gcc $(target_cflags) -fPIC -DLUA_USE_LINUX \
            -I"$PACKAGE_SOURCE/src" -c "$source_file" -o "$object"
    done
    gcc $(target_ldflags) -shared -Wl,-soname,liblua.so.5.4 \
        -o "$PACKAGE_STAGING/usr/lib/liblua.so.$LUA_VERSION" \
        "$PACKAGE_BUILD"/objects/*.o -ldl -lm
    ln -s "liblua.so.$LUA_VERSION" "$PACKAGE_STAGING/usr/lib/liblua.so.5.4"
    ln -s liblua.so.5.4 "$PACKAGE_STAGING/usr/lib/liblua.so"
    install -m644 "$PACKAGE_SOURCE"/src/{lua.h,lauxlib.h,lualib.h,luaconf.h} \
        "$PACKAGE_STAGING/usr/include/"
    cat > "$PACKAGE_STAGING/usr/lib/pkgconfig/lua.pc" <<PC
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: Lua
Description: Lua language engine
Version: $LUA_VERSION
Libs: -L\${libdir} -llua -lm -ldl
Cflags: -I\${includedir}
PC
    publish_package "$package"
fi

package="duktape-$DUKTAPE_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$DUKTAPE_SHA256" \
        "https://duktape.org/$package.tar.xz"
    make -C "$PACKAGE_SOURCE" -f Makefile.sharedlibrary \
        CC=gcc \
        CFLAGS="$(target_cflags) -fPIC" \
        LDFLAGS="$(target_ldflags)" \
        INSTALL_PREFIX=/usr LIBDIR=/lib
    make -C "$PACKAGE_SOURCE" -f Makefile.sharedlibrary install \
        DESTDIR="$PACKAGE_STAGING" INSTALL_PREFIX=/usr LIBDIR=/lib
    rm -f "$PACKAGE_STAGING/usr/lib"/libduktaped.so*
    publish_package "$package"
fi

package="alsa-lib-$ALSA_LIB_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.bz2" "$ALSA_LIB_SHA256" \
        "https://www.alsa-project.org/files/pub/lib/$package.tar.bz2"
    configure_target "$PACKAGE_SOURCE" --disable-static --disable-python
    make_target
    publish_package "$package"
fi

package="ell-$ELL_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$ELL_SHA256" \
        "https://mirrors.edge.kernel.org/pub/linux/libs/ell/$package.tar.xz"
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --disable-glib \
        --disable-tests \
        --disable-tools \
        --disable-examples
    make_target
    publish_package "$package"
fi

package="libnl-$LIBNL_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$LIBNL_SHA256" \
        "https://github.com/thom311/libnl/archive/refs/tags/libnl${LIBNL_VERSION//./_}.tar.gz"
    (cd "$PACKAGE_SOURCE" && autoreconf -fi)
    configure_target "$PACKAGE_SOURCE" --disable-static
    make_target
    publish_package "$package"
fi

package="jansson-$JANSSON_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$JANSSON_SHA256" \
        "https://github.com/akheron/jansson/releases/download/v$JANSSON_VERSION/$package.tar.gz"
    configure_target "$PACKAGE_SOURCE" --disable-static
    make_target
    publish_package "$package"
fi

package="libndp-$LIBNDP_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$LIBNDP_SHA256" \
        "https://github.com/jpirko/libndp/archive/refs/tags/v$LIBNDP_VERSION.tar.gz"
    (cd "$PACKAGE_SOURCE" && autoreconf -fi)
    configure_target "$PACKAGE_SOURCE" --disable-static
    make_target
    publish_package "$package"
fi

package="libarchive-$LIBARCHIVE_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$LIBARCHIVE_SHA256" \
        "https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VERSION/$package.tar.xz"
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --disable-bsdtar \
        --disable-bsdcpio \
        --disable-bsdcat \
        --without-bz2lib \
        --without-libb2 \
        --without-lz4 \
        --without-nettle \
        --without-openssl \
        --without-xml2 \
        --without-expat
    make_target
    publish_package "$package"
fi

package="fuse-$FUSE3_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$FUSE3_SHA256" \
        "https://github.com/libfuse/libfuse/releases/download/fuse-$FUSE3_VERSION/$package.tar.gz"
    meson_target "$PACKAGE_SOURCE" \
        -Dexamples=false \
        -Dtests=false \
        -Duseroot=false \
        -Dudevrulesdir=/usr/lib/udev/rules.d
    publish_package "$package"
fi

package="sqlite-$SQLITE_VERSION"
if ! restore_package "$package"; then
    archive="$EFILINUX_DOWNLOADS/sqlite-src-$SQLITE_SOURCE_VERSION.zip"
    prepare_package "$package"
    download \
        "https://www.sqlite.org/2026/sqlite-src-$SQLITE_SOURCE_VERSION.zip" \
        "$archive"
    verify_sha256 "$SQLITE_SHA256" "$archive"
    temporary=$(mktemp -d)
    unzip -q "$archive" -d "$temporary"
    cp -a "$temporary/sqlite-src-$SQLITE_SOURCE_VERSION/." "$PACKAGE_SOURCE/"
    rm -rf "$temporary"
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --disable-readline \
        --soname=legacy
    make_target
    publish_package "$package"
fi

package="dconf-$DCONF_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$DCONF_SHA256" \
        "https://download.gnome.org/sources/dconf/${DCONF_VERSION%.*}/$package.tar.xz"
    meson_target "$PACKAGE_SOURCE" \
        -Dbash_completion=false \
        -Dman=false \
        -Dgtk_doc=false \
        -Dvapi=false \
        -Dsystemduserunitdir=''
    publish_package "$package"
fi

package="libgpg-error-$LIBGPG_ERROR_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.bz2" "$LIBGPG_ERROR_SHA256" \
        "https://www.gnupg.org/ftp/gcrypt/libgpg-error/$package.tar.bz2"
    configure_target "$PACKAGE_SOURCE" --disable-static --disable-doc --disable-tests
    make_target
    publish_package "$package"
fi

package="libgcrypt-$LIBGCRYPT_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.bz2" "$LIBGCRYPT_SHA256" \
        "https://gnupg.org/ftp/gcrypt/libgcrypt/$package.tar.bz2"
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --disable-doc \
        --disable-tests \
        --disable-jent-support
    make_target
    publish_package "$package"
fi

package="gsettings-desktop-schemas-$GSETTINGS_SCHEMAS_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$GSETTINGS_SCHEMAS_SHA256" \
        "https://download.gnome.org/sources/gsettings-desktop-schemas/${GSETTINGS_SCHEMAS_VERSION%.*}/$package.tar.xz"
    meson_target "$PACKAGE_SOURCE" -Dintrospection=false
    publish_package "$package"
fi

package="libsecret-$LIBSECRET_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$LIBSECRET_SHA256" \
        "https://download.gnome.org/sources/libsecret/${LIBSECRET_VERSION%.*}/$package.tar.xz"
    meson_target "$PACKAGE_SOURCE" \
        -Dcrypto=libgcrypt \
        -Dmanpage=false \
        -Dvapi=false \
        -Dgtk_doc=false \
        -Dintrospection=false \
        -Dbash_completion=disabled \
        -Dtpm2=false \
        -Dpam=false
    publish_package "$package"
fi
