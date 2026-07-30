#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=librsvg
pkgver=2.58.5

depends=(cairo fontconfig freetype gdk-pixbuf glib glibc libxml2 pango)
builddepends=()
makedepends=(autoreconf cargo gcc make pkg-config rustc)

prepare() {
    local archive="$downloaddir/librsvg-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/librsvg/2.58/librsvg-$pkgver.tar.xz" "$archive"
    checksum sha256 224233a0e347d38c415f15a49f0e0885313e3ecc18f3192055f9304dd2f3a27a "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    cargo_vendor "$srcdir/source/Cargo.toml" "$srcdir/source/vendor"
}

build() {
    local rustflags="-C target-cpu=$EFILINUX_X86_64_LEVEL -C linker=gcc"
    local flag gdk_version gdk_directory
    local -a linker_flags=()

    read -r -a linker_flags <<< "$LDFLAGS"
    for flag in "${linker_flags[@]}"; do
        rustflags+=" -C link-arg=$flag"
    done

    export CARGO_HOME="$recipework/cargo-home"
    export CARGO_NET_OFFLINE=true
    export CARGO_BUILD_JOBS="$EFILINUX_JOBS"
    export RUSTFLAGS="$rustflags"
    export PKG_CONFIG_ALLOW_CROSS=1

    target_autotools_configure "$srcdir/source" "$builddir" \
        --disable-static \
        --enable-shared \
        --disable-gtk-doc \
        --disable-installed-tests \
        --disable-always-build-tests \
        --enable-pixbuf-loader \
        --enable-introspection=no \
        --enable-vala=no

    gdk_version=$(target_pkg_config --variable=gdk_pixbuf_binary_version gdk-pixbuf-2.0)
    [[ -n "$gdk_version" ]] || die "gdk-pixbuf did not report its binary module version"
    gdk_directory="/usr/lib/gdk-pixbuf-2.0/$gdk_version"
    sed -i \
        -e "s#^gdk_pixbuf_binarydir = .*#gdk_pixbuf_binarydir = $gdk_directory#" \
        -e "s#^gdk_pixbuf_moduledir = .*#gdk_pixbuf_moduledir = $gdk_directory/loaders#" \
        -e "s#^gdk_pixbuf_cache_file = .*#gdk_pixbuf_cache_file = $gdk_directory/loaders.cache#" \
        "$builddir/gdk-pixbuf-loader/Makefile"

    make -C "$builddir" -j"$EFILINUX_JOBS"
    GDK_PIXBUF_QUERYLOADERS=: make -C "$builddir" DESTDIR="$develdir" install
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    rm -f "$develdir$gdk_directory/loaders.cache" "$develdir/usr/bin/rsvg-convert"
    rm -rf "$develdir/usr/share/doc" "$develdir/usr/share/man" "$develdir/usr/share/thumbnailers"
    target_normalize_pkg_config "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local loader
    local -a keep=()
    package_add_library_family keep 'librsvg-2.so.2*'
    loader=$(find "$pkgdir/usr/lib/gdk-pixbuf-2.0" -type f -name libpixbufloader-svg.so -print -quit)
    [[ -n "$loader" ]] || die "librsvg SVG loader is missing"
    keep+=("${loader#$pkgdir}")
    package_keep "${keep[@]}"
}

recipe_main "$@"
