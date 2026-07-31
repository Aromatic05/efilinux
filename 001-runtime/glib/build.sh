#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=glib
pkgver=2.88.2

depends=(
    glibc
    libffi
    pcre2
    zlib
)
builddepends=(
    linux-headers
)
makedepends=(
    gcc
    meson
    ninja
    pkg-config
    python3
)

prepare() {
    local archive="$downloaddir/glib-$pkgver.tar.xz"

    download \
        "https://download.gnome.org/sources/glib/${pkgver%.*}/glib-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        cf3f215a640c8a4257f14317586b8f1fdd25a10a93cb4bdda147c0f9ad88e74f \
        "$archive"
    extract "$archive" "$srcdir/glib"
}

build() {
    log "Configuring generic GLib runtime"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/glib" \
            --prefix=/usr \
            --libdir=lib \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dselinux=disabled \
            -Dlibmount=disabled \
            -Dman-pages=disabled \
            -Ddtrace=disabled \
            -Dsystemtap=disabled \
            -Dsysprof=disabled \
            -Ddocumentation=false \
            -Dtests=false \
            -Dinstalled_tests=false \
            -Dnls=enabled \
            -Dglib_debug=disabled \
            -Dintrospection=disabled \
            -Dlibelf=disabled \
            -Dfile_monitor_backend=inotify

    log "Building generic GLib runtime"
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local pattern library relative
    local -a keep=(
        /usr/bin/gdbus
        /usr/bin/gio
        /usr/bin/gio-querymodules
        /usr/bin/glib-compile-schemas
        /usr/bin/gsettings
    )
    local -a libraries=()

    for pattern in \
        'libglib-2.0.so.0*' \
        'libgobject-2.0.so.0*' \
        'libgio-2.0.so.0*' \
        'libgmodule-2.0.so.0*' \
        'libgthread-2.0.so.0*'; do
        libraries=()
        mapfile -d '' -t libraries < <(
            find "$pkgdir/usr/lib" -maxdepth 1 \
                \( -type f -o -type l \) \
                -name "$pattern" \
                -print0 | LC_ALL=C sort -z
        )
        ((${#libraries[@]} > 0)) || die "GLib runtime library is missing: $pattern"
        for library in "${libraries[@]}"; do
            relative=/${library#"$pkgdir/"}
            keep+=("$relative")
        done
    done

    if [[ -d "$pkgdir/usr/lib/gio" ]]; then
        keep+=(/usr/lib/gio/)
    fi
    package_keep "${keep[@]}"
}

recipe_main "$@"
