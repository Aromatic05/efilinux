#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command cmake curl gcc meson nasm ninja pkg-config python3 sha256sum tar
ensure_directories

build_meson_component() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    if graphical_binary_package_restore "$package"; then
        return
    fi
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
}

build_freetype() {
    local package=$1
    local harfbuzz=$2

    if graphical_binary_package_restore "$package"; then
        return
    fi
    graphical_prepare_archive \
        "$package" \
        "freetype-$FREETYPE_VERSION.tar.xz" \
        "$FREETYPE_SHA256" \
        "https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        -Dbrotli=disabled \
        -Dbzip2=disabled \
        -Dharfbuzz="$harfbuzz" \
        -Dmmap=enabled \
        -Dpng=enabled \
        -Dtests=disabled \
        -Dzlib=system
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
}

package="libpng-$LIBPNG_VERSION"
if ! graphical_binary_package_restore "$package"; then
    graphical_prepare_archive \
        "$package" \
        "libpng-$LIBPNG_VERSION.tar.gz" \
        "$LIBPNG_SHA256" \
        "https://download.sourceforge.net/libpng/libpng-$LIBPNG_VERSION.tar.gz"
    graphical_cmake_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        -DPNG_SHARED=ON \
        -DPNG_STATIC=OFF \
        -DPNG_TESTS=OFF \
        -DPNG_TOOLS=OFF \
        -DPNG_EXECUTABLES=OFF
    graphical_cmake_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
fi

package="libjpeg-turbo-$LIBJPEG_TURBO_VERSION"
if ! graphical_binary_package_restore "$package"; then
    graphical_prepare_archive \
        "$package" \
        "libjpeg-turbo-$LIBJPEG_TURBO_VERSION.tar.gz" \
        "$LIBJPEG_TURBO_SHA256" \
        "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$LIBJPEG_TURBO_VERSION/libjpeg-turbo-$LIBJPEG_TURBO_VERSION.tar.gz"
    graphical_cmake_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        -DENABLE_SHARED=ON \
        -DENABLE_STATIC=OFF \
        -DWITH_SIMD=ON \
        -DWITH_TURBOJPEG=OFF \
        -DWITH_TOOLS=OFF \
        -DWITH_TESTS=OFF \
        -DWITH_FUZZ=OFF
    graphical_cmake_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
fi

build_freetype "freetype-bootstrap-$FREETYPE_VERSION" disabled

build_meson_component \
    "fontconfig-$FONTCONFIG_VERSION" \
    "fontconfig-$FONTCONFIG_VERSION.tar.gz" \
    "$FONTCONFIG_SHA256" \
    "https://www.freedesktop.org/software/fontconfig/release/fontconfig-$FONTCONFIG_VERSION.tar.gz" \
    -Ddoc=disabled \
    -Ddoc-txt=disabled \
    -Ddoc-man=disabled \
    -Ddoc-pdf=disabled \
    -Ddoc-html=disabled \
    -Dnls=disabled \
    -Dtests=disabled \
    -Dtests-bwrap=disabled \
    -Dtests-external-fonts=disabled \
    -Dtools=enabled \
    -Dcache-build=disabled \
    -Diconv=disabled \
    -Dxml-backend=expat \
    -Dfontations=disabled

build_meson_component \
    "harfbuzz-$HARFBUZZ_VERSION" \
    "harfbuzz-$HARFBUZZ_VERSION.tar.xz" \
    "$HARFBUZZ_SHA256" \
    "https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz" \
    -Dglib=disabled \
    -Dgobject=disabled \
    -Dcairo=disabled \
    -Dchafa=disabled \
    -Dpng=enabled \
    -Dzlib=enabled \
    -Dicu=disabled \
    -Dgraphite2=disabled \
    -Dfreetype=enabled \
    -Dfontations=disabled \
    -Dharfrust=disabled \
    -Dkbts=disabled \
    -Dwasm=disabled \
    -Draster=enabled \
    -Dvector=enabled \
    -Dgpu=disabled \
    -Dgpu_demo=disabled \
    -Dsubset=enabled \
    -Dtests=disabled \
    -Dintrospection=disabled \
    -Ddocs=disabled \
    -Dutilities=disabled \
    -Dbenchmark=disabled

build_freetype "freetype-$FREETYPE_VERSION" enabled

build_meson_component \
    "fribidi-$FRIBIDI_VERSION" \
    "fribidi-$FRIBIDI_VERSION.tar.xz" \
    "$FRIBIDI_SHA256" \
    "https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz" \
    -Ddeprecated=false \
    -Ddocs=false \
    -Dbin=false \
    -Dtests=false

build_meson_component \
    "pixman-$PIXMAN_VERSION" \
    "pixman-$PIXMAN_VERSION.tar.gz" \
    "$PIXMAN_SHA256" \
    "https://gitlab.freedesktop.org/pixman/pixman/-/archive/pixman-$PIXMAN_VERSION/pixman-pixman-$PIXMAN_VERSION.tar.gz" \
    -Dopenmp=disabled \
    -Dgtk=disabled \
    -Dlibpng=disabled \
    -Dtests=disabled \
    -Ddemos=disabled \
    -Dtimers=false \
    -Dgnuplot=false

package="dejavu-fonts-$DEJAVU_FONTS_VERSION"
if ! graphical_binary_package_restore "$package"; then
    prepare_package "$package"
    archive="dejavu-fonts-ttf-$DEJAVU_FONTS_VERSION.tar.bz2"
    download \
        "https://downloads.sourceforge.net/dejavu/$archive" \
        "$EFILINUX_DOWNLOADS/$archive"
    verify_sha256 "$DEJAVU_FONTS_SHA256" "$EFILINUX_DOWNLOADS/$archive"
    extract_source "$EFILINUX_DOWNLOADS/$archive" "$PACKAGE_SOURCE"
    mkdir -p "$PACKAGE_STAGING/usr/share/fonts/truetype/dejavu"
    find "$PACKAGE_SOURCE/ttf" -maxdepth 1 -type f -name '*.ttf' \
        -exec install -m 0644 -t "$PACKAGE_STAGING/usr/share/fonts/truetype/dejavu" {} +
    graphical_binary_package_publish "$package"
fi

for artifact in \
    usr/lib/libpng16.so.16 \
    usr/lib/libjpeg.so.62 \
    usr/lib/libfreetype.so.6 \
    usr/lib/libfontconfig.so.1 \
    usr/lib/libharfbuzz.so.0 \
    usr/lib/libfribidi.so.0 \
    usr/lib/libpixman-1.so.0 \
    usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
    usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf \
    etc/fonts/fonts.conf; do
    [[ -e "$EFILINUX_SYSROOT/$artifact" ]] || \
        die "text stack artifact is missing: /$artifact"
done

for dependency in libpng libjpeg freetype2 fontconfig harfbuzz fribidi pixman-1; do
    target_pkg_config --exists "$dependency" || \
        die "text stack pkg-config dependency is missing: $dependency"
done
