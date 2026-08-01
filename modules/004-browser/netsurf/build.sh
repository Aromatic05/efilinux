#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=netsurf
pkgver=3.11

depends=(curl duktape gcc-libs glib glibc gtk3 libjpeg-turbo libpng librsvg openssl zlib)
builddepends=()
makedepends=(gcc make perl pkg-config)

prepare() {
    local archive="$downloaddir/netsurf-all-$pkgver.tar.gz"

    download "https://download.netsurf-browser.org/netsurf/releases/source-full/netsurf-all-$pkgver.tar.gz" "$archive"
    checksum sha256 4dea880ff3c2f698bfd62c982b259340f9abcd7f67e6c8eb2b32c61f71644b7b "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    cat > "$srcdir/source/netsurf/Makefile.config" <<'CONFIG'
# Keep the GTK browser usable without enabling optional media and image stacks.
override NETSURF_USE_CURL := YES
override NETSURF_USE_OPENSSL := YES
override NETSURF_USE_DUKTAPE := YES
override NETSURF_USE_JPEGXL := NO
override NETSURF_USE_VIDEO := NO
override NETSURF_USE_WEBP := NO
override NETSURF_USE_RSVG := YES
override NETSURF_USE_GRESOURCE := YES
override NETSURF_STRIP_BINARY := YES
CONFIG

    target_env make -C "$srcdir/source" TARGET=gtk3 PREFIX=/usr \
        HOST="$(gcc -dumpmachine)" BUILD="$(gcc -dumpmachine)" \
        PKGCONFIG='PKG_CONFIG_SYSROOT_DIR= PKG_CONFIG_PATH="$(PREFIX)/lib/pkgconfig:$(PKG_CONFIG_PATH)" pkg-config' \
        PKG_CONFIG='PKG_CONFIG_SYSROOT_DIR= PKG_CONFIG_PATH="$(CURDIR)/inst-gtk3/lib/pkgconfig:$(PKG_CONFIG_PATH)" pkg-config' \
        -j"$EFILINUX_JOBS"
    target_env make -C "$srcdir/source" TARGET=gtk3 PREFIX=/usr \
        HOST="$(gcc -dumpmachine)" BUILD="$(gcc -dumpmachine)" \
        PKGCONFIG='PKG_CONFIG_SYSROOT_DIR= PKG_CONFIG_PATH="$(PREFIX)/lib/pkgconfig:$(PKG_CONFIG_PATH)" pkg-config' \
        PKG_CONFIG='PKG_CONFIG_SYSROOT_DIR= PKG_CONFIG_PATH="$(CURDIR)/inst-gtk3/lib/pkgconfig:$(PKG_CONFIG_PATH)" pkg-config' \
        DESTDIR="$develdir" install

    install -Dm0644 "$srcdir/source/netsurf/frontends/gtk/res/netsurf-gtk.desktop" \
        "$develdir/usr/share/applications/netsurf.desktop"
    sed -i -e 's/^Exec=netsurf-gtk %u$/Exec=netsurf-gtk3 %u/' \
        -e 's/^Icon=netsurf.png$/Icon=netsurf/' \
        "$develdir/usr/share/applications/netsurf.desktop"
    install -Dm0644 "$srcdir/source/netsurf/frontends/gtk/res/netsurf.png" \
        "$develdir/usr/share/icons/hicolor/48x48/apps/netsurf.png"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/netsurf-gtk3 \
        /usr/share/applications/netsurf.desktop \
        /usr/share/icons/hicolor/48x48/apps/netsurf.png \
        /usr/share/netsurf/
}

recipe_main "$@"
