#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command cargo curl gcc make meson ninja pkg-config python3 readelf rustc sha256sum tar
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
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" \
        graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" \
        graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
}

build_librsvg_component() {
    local package="librsvg-$LIBRSVG_VERSION"
    local rustflags="-C target-cpu=$EFILINUX_X86_64_LEVEL -C linker=gcc"
    local gdk_pixbuf_binary_version
    local gdk_pixbuf_binarydir
    local flag
    local -a linker_flags

    if graphical_binary_package_restore "$package"; then
        return
    fi

    graphical_prepare_archive \
        "$package" \
        "$package.tar.xz" \
        "$LIBRSVG_SHA256" \
        "https://download.gnome.org/sources/librsvg/${LIBRSVG_VERSION%.*}/$package.tar.xz"

    read -r -a linker_flags <<< "$(target_ldflags)"
    for flag in "${linker_flags[@]}"; do
        rustflags+=" -C link-arg=$flag"
    done

    CARGO_HOME="$EFILINUX_BUILD/cargo-home" \
    CARGO_BUILD_JOBS="$EFILINUX_JOBS" \
    RUSTFLAGS="$rustflags" \
    PKG_CONFIG_ALLOW_CROSS=1 \
        graphical_autotools_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --enable-shared \
        --disable-gtk-doc \
        --disable-installed-tests \
        --disable-always-build-tests \
        --enable-pixbuf-loader \
        --enable-introspection=no \
        --enable-vala=no

    gdk_pixbuf_binary_version=$(target_pkg_config \
        --variable=gdk_pixbuf_binary_version gdk-pixbuf-2.0)
    [[ -n "$gdk_pixbuf_binary_version" ]] || \
        die "gdk-pixbuf did not report its binary module version"
    gdk_pixbuf_binarydir="/usr/lib/gdk-pixbuf-2.0/$gdk_pixbuf_binary_version"
    sed -i \
        -e "s#^gdk_pixbuf_binarydir = .*#gdk_pixbuf_binarydir = $gdk_pixbuf_binarydir#" \
        -e "s#^gdk_pixbuf_moduledir = .*#gdk_pixbuf_moduledir = $gdk_pixbuf_binarydir/loaders#" \
        -e "s#^gdk_pixbuf_cache_file = .*#gdk_pixbuf_cache_file = $gdk_pixbuf_binarydir/loaders.cache#" \
        "$PACKAGE_BUILD/gdk-pixbuf-loader/Makefile"

    CARGO_HOME="$EFILINUX_BUILD/cargo-home" \
    CARGO_BUILD_JOBS="$EFILINUX_JOBS" \
    RUSTFLAGS="$rustflags" \
    PKG_CONFIG_ALLOW_CROSS=1 \
        make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    CARGO_HOME="$EFILINUX_BUILD/cargo-home" \
    CARGO_BUILD_JOBS="$EFILINUX_JOBS" \
    RUSTFLAGS="$rustflags" \
    PKG_CONFIG_ALLOW_CROSS=1 \
    GDK_PIXBUF_QUERYLOADERS=: \
        make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    find "$PACKAGE_STAGING/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    rm -f "$PACKAGE_STAGING$gdk_pixbuf_binarydir/loaders.cache"
    graphical_normalize_pkg_config "$PACKAGE_STAGING"

    rm -f "$PACKAGE_STAGING/usr/bin/rsvg-convert"
    rm -rf \
        "$PACKAGE_STAGING/usr/share/doc" \
        "$PACKAGE_STAGING/usr/share/man" \
        "$PACKAGE_STAGING/usr/share/thumbnailers"
    if grep -R -Fq "$EFILINUX_SYSROOT" "$PACKAGE_STAGING"; then
        die "librsvg package contains a build sysroot path"
    fi
    if [[ -e "$PACKAGE_STAGING/home" ]]; then
        die "librsvg package contains a build-host directory tree"
    fi
    graphical_binary_package_publish "$package"
}

ensure_pkg_component() {
    local dependency=$1
    local expected_version=$2
    shift 2

    if ! target_pkg_config --exact-version="$expected_version" "$dependency"; then
        "$@"
    fi
}

if ! target_pkg_config --exists epoxy; then
    "$ROOT/003-graphical/libepoxy/build.sh"
fi

target_pkg_config --exists xtst || \
    die "libXtst must be built before the GTK accessibility stack"

target_pkg_config --exact-version="$GLIB_VERSION" glib-2.0 || \
    die "GLib $GLIB_VERSION must be built by 001-runtime before GTK"

ensure_pkg_component libxml-2.0 "$LIBXML2_VERSION" build_meson_component \
    "libxml2-$LIBXML2_VERSION" \
    "libxml2-$LIBXML2_VERSION.tar.xz" \
    "$LIBXML2_SHA256" \
    "https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-$LIBXML2_VERSION.tar.xz" \
    -Ddocs=disabled \
    -Ddebugging=disabled \
    -Dhistory=disabled \
    -Dicu=disabled \
    -Dlegacy=disabled \
    -Dmodules=disabled \
    -Dpython=disabled \
    -Dreadline=disabled \
    -Diconv=enabled \
    -Dthreads=enabled \
    -Dzlib=enabled

ensure_pkg_component atspi-2 "$AT_SPI2_CORE_VERSION" build_meson_component \
    "at-spi2-core-$AT_SPI2_CORE_VERSION" \
    "at-spi2-core-$AT_SPI2_CORE_VERSION.tar.xz" \
    "$AT_SPI2_CORE_SHA256" \
    "https://download.gnome.org/sources/at-spi2-core/${AT_SPI2_CORE_VERSION%.*}/at-spi2-core-$AT_SPI2_CORE_VERSION.tar.xz" \
    -Ddefault_bus=dbus-daemon \
    -Ddbus_daemon=/usr/bin/dbus-daemon \
    -Duse_systemd=false \
    -Dgtk2_atk_adaptor=false \
    -Ddocs=false \
    -Dintrospection=disabled \
    -Dx11=enabled \
    -Ddbus_glib=disabled

rm -f "$EFILINUX_SYSROOT/etc/xdg/Xwayland-session.d/00-at-spi"
rmdir "$EFILINUX_SYSROOT/etc/xdg/Xwayland-session.d" 2>/dev/null || true

ensure_pkg_component gdk-pixbuf-2.0 "$GDK_PIXBUF_VERSION" build_meson_component \
    "gdk-pixbuf-$GDK_PIXBUF_VERSION" \
    "gdk-pixbuf-$GDK_PIXBUF_VERSION.tar.xz" \
    "$GDK_PIXBUF_SHA256" \
    "https://download.gnome.org/sources/gdk-pixbuf/${GDK_PIXBUF_VERSION%.*}/gdk-pixbuf-$GDK_PIXBUF_VERSION.tar.xz" \
    -Dpng=enabled \
    -Djpeg=enabled \
    -Dgif=enabled \
    -Dtiff=disabled \
    -Dglycin=disabled \
    -Dandroid=disabled \
    -Dothers=disabled \
    -Dbuiltin_loaders=png,jpeg,gif \
    -Ddocumentation=false \
    -Dintrospection=disabled \
    -Dman=false \
    -Dtests=false \
    -Dinstalled_tests=false \
    -Dgio_sniffing=false \
    -Dthumbnailer=disabled \
    -Dlegacy_xpm=disabled

ensure_pkg_component cairo "$CAIRO_VERSION" build_meson_component \
    "cairo-$CAIRO_VERSION" \
    "cairo-$CAIRO_VERSION.tar.xz" \
    "$CAIRO_SHA256" \
    "https://cairographics.org/releases/cairo-$CAIRO_VERSION.tar.xz" \
    -Ddwrite=disabled \
    -Dfontconfig=enabled \
    -Dfreetype=enabled \
    -Dpng=enabled \
    -Dquartz=disabled \
    -Dtee=disabled \
    -Dxcb=enabled \
    -Dxlib=enabled \
    -Dxlib-xcb=enabled \
    -Dzlib=enabled \
    -Dtests=disabled \
    -Dlzo=disabled \
    -Dgtk2-utils=disabled \
    -Dglib=enabled \
    -Dspectre=disabled \
    -Dsymbol-lookup=disabled \
    -Dgtk_doc=false

ensure_pkg_component xft "$LIBXFT_VERSION" "$ROOT/003-graphical/libxft/build.sh"

ensure_pkg_component pango "$PANGO_VERSION" build_meson_component \
    "pango-$PANGO_VERSION" \
    "pango-$PANGO_VERSION.tar.xz" \
    "$PANGO_SHA256" \
    "https://download.gnome.org/sources/pango/${PANGO_VERSION%.*}/pango-$PANGO_VERSION.tar.xz" \
    -Ddocumentation=false \
    -Dman-pages=false \
    -Dintrospection=disabled \
    -Dbuild-testsuite=false \
    -Dbuild-examples=false \
    -Dfontconfig=enabled \
    -Dsysprof=disabled \
    -Dlibthai=disabled \
    -Dcairo=enabled \
    -Dxft=enabled \
    -Dfreetype=enabled

if ! target_pkg_config --exact-version="$LIBRSVG_VERSION" librsvg-2.0 || \
   [[ ! -f "$EFILINUX_SYSROOT/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-svg.so" ]]; then
    build_librsvg_component
fi

ensure_pkg_component gtk+-3.0 "$GTK3_VERSION" build_meson_component \
    "gtk-$GTK3_VERSION" \
    "gtk-$GTK3_VERSION.tar.gz" \
    "$GTK3_SHA256" \
    "https://gitlab.gnome.org/GNOME/gtk/-/archive/$GTK3_VERSION/gtk-$GTK3_VERSION.tar.gz" \
    -Dx11_backend=true \
    -Dwayland_backend=false \
    -Dbroadway_backend=false \
    -Dwin32_backend=false \
    -Dquartz_backend=false \
    -Dxinerama=yes \
    -Dcloudproviders=false \
    -Dprofiler=false \
    -Dtracker3=false \
    -Dprint_backends=file \
    -Dcolord=no \
    -Dgtk_doc=false \
    -Dman=false \
    -Dintrospection=false \
    -Ddemos=true \
    -Dexamples=false \
    -Dtests=false \
    -Dinstalled_tests=false \
    -Dbuiltin_immodules=xim

for artifact in \
    usr/lib/libglib-2.0.so.0 \
    usr/lib/libgio-2.0.so.0 \
    usr/lib/libxml2.so.16 \
    usr/lib/libatk-1.0.so.0 \
    usr/lib/libatk-bridge-2.0.so.0 \
    usr/lib/libatspi.so.0 \
    usr/lib/libgdk_pixbuf-2.0.so.0 \
    usr/lib/libcairo.so.2 \
    usr/lib/libcairo-gobject.so.2 \
    usr/lib/libpango-1.0.so.0 \
    usr/lib/libpangocairo-1.0.so.0 \
    usr/lib/librsvg-2.so.2 \
    usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-svg.so \
    usr/lib/libgtk-3.so.0 \
    usr/lib/libgdk-3.so.0 \
    usr/bin/gtk3-demo \
    usr/libexec/at-spi-bus-launcher \
    usr/libexec/at-spi2-registryd; do
    [[ -e "$EFILINUX_SYSROOT/$artifact" ]] || \
        die "GTK 3 toolkit artifact is missing: /$artifact"
done

for dependency in \
    glib-2.0 gio-2.0 gio-unix-2.0 gmodule-2.0 gobject-2.0 \
    libxml-2.0 atk atspi-2 atk-bridge-2.0 gdk-pixbuf-2.0 \
    cairo cairo-gobject pango pangoft2 pangocairo librsvg-2.0 \
    gtk+-3.0 gdk-x11-3.0; do
    target_pkg_config --exists "$dependency" || \
        die "GTK 3 toolkit pkg-config dependency is missing: $dependency"
done

if find "$EFILINUX_SYSROOT" \
    \( -name 'libwayland-*.so*' \
       -o -name 'wayland-*.pc' \
       -o -name 'wayland-*.h' \
       -o -name Xwayland \
       -o -path '*/wayland-protocols/*' \) \
    -print -quit | grep -q .; then
    die "Wayland artifacts leaked into the GTK 3 toolkit sysroot"
fi

if LC_ALL=C readelf -d "$EFILINUX_SYSROOT/usr/lib/libgtk-3.so.0" | grep -Ei 'wayland'; then
    die "GTK 3 runtime links against Wayland"
fi
