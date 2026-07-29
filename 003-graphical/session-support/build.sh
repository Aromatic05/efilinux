#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/003-graphical/session-support/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command autoreconf curl find gcc make meson ninja pkg-config sha256sum tar
ensure_directories

recipe_inputs=(
    "$ROOT/001-runtime/config.sh"
    "$ROOT/002-system/desktop-config.sh"
    "$ROOT/003-graphical/config.sh"
    "$ROOT/003-graphical/session-support/config.sh"
    "$ROOT/003-graphical/lib/build.sh"
)

restore_package() {
    binary_package_restore_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

publish_package() {
    find "$PACKAGE_STAGING" -type f -name '*.la' -delete 2>/dev/null || true
    binary_package_publish_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

prune_translations() {
    local locale_directory="$1/usr/share/locale"
    local entry

    [[ -d "$locale_directory" ]] || return 0
    while IFS= read -r -d '' entry; do
        case $(basename -- "$entry") in
            en|en_US|zh_CN|zh_Hans) ;;
            *) rm -rf -- "$entry" ;;
        esac
    done < <(find "$locale_directory" -mindepth 1 -maxdepth 1 -print0)
}

build_autotools_snapshot() {
    local package=$1 archive=$2 sha256=$3 url=$4
    shift 4

    restore_package "$package" && return
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_autotools_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --disable-silent-rules \
        "$@"
    make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
    publish_package "$package"
}

build_release_archive() {
    local package=$1 archive=$2 sha256=$3 url=$4
    shift 4

    restore_package "$package" && return
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_release_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --disable-silent-rules \
        "$@"
    make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
    publish_package "$package"
}

build_meson_archive() {
    local package=$1 archive=$2 sha256=$3 url=$4
    shift 4

    restore_package "$package" && return
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
    publish_package "$package"
}

package="iso-codes-$ISO_CODES_VERSION"
if ! restore_package "$package"; then
    graphical_prepare_archive \
        "$package" "iso-codes-$ISO_CODES_VERSION.tar.gz" "$ISO_CODES_SHA256" \
        "https://salsa.debian.org/iso-codes-team/iso-codes/-/archive/v$ISO_CODES_VERSION/iso-codes-v$ISO_CODES_VERSION.tar.gz"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD"
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"

    compact="$PACKAGE_BUILD/compact-iso-codes"
    rm -rf "$compact"
    mkdir -p \
        "$compact/usr/share/pkgconfig" \
        "$compact/usr/share/xml/iso-codes" \
        "$compact/usr/share/locale/zh_CN/LC_MESSAGES"
    cp "$PACKAGE_STAGING/usr/share/pkgconfig/iso-codes.pc" \
        "$compact/usr/share/pkgconfig/"
    for domain in iso_639-2 iso_3166-1; do
        cp "$PACKAGE_STAGING/usr/share/xml/iso-codes/$domain.xml" \
            "$compact/usr/share/xml/iso-codes/"
        cp "$PACKAGE_STAGING/usr/share/locale/zh_CN/LC_MESSAGES/$domain.mo" \
            "$compact/usr/share/locale/zh_CN/LC_MESSAGES/"
    done
    ln -s iso_639-2.xml "$compact/usr/share/xml/iso-codes/iso_639.xml"
    ln -s iso_3166-1.xml "$compact/usr/share/xml/iso-codes/iso_3166.xml"
    ln -s iso_639-2.mo \
        "$compact/usr/share/locale/zh_CN/LC_MESSAGES/iso_639.mo"
    ln -s iso_3166-1.mo \
        "$compact/usr/share/locale/zh_CN/LC_MESSAGES/iso_3166.mo"
    rm -rf "$PACKAGE_STAGING"
    mv "$compact" "$PACKAGE_STAGING"
    publish_package "$package"
fi

build_autotools_snapshot \
    "libXScrnSaver-$LIBXSS_VERSION" \
    "libXScrnSaver-$LIBXSS_VERSION.tar.gz" \
    "$LIBXSS_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxscrnsaver/-/archive/libXScrnSaver-$LIBXSS_VERSION/libxscrnsaver-libXScrnSaver-$LIBXSS_VERSION.tar.gz"

package="libxklavier-$LIBXKLAVIER_VERSION"
if ! restore_package "$package"; then
    graphical_prepare_archive \
        "$package" "libxklavier-$LIBXKLAVIER_VERSION.tar.gz" "$LIBXKLAVIER_SHA256" \
        "https://gitlab.freedesktop.org/archived-projects/libxklavier/-/archive/libxklavier-$LIBXKLAVIER_VERSION/libxklavier-libxklavier-$LIBXKLAVIER_VERSION.tar.gz"
    sed -i \
        's#iso_codes_prefix=`$PKG_CONFIG --variable=prefix iso-codes`#iso_codes_prefix=/usr#' \
        "$PACKAGE_SOURCE/configure.ac"
    graphical_autotools_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --disable-silent-rules \
        --disable-gtk-doc \
        --disable-introspection \
        --with-xkb-base=/usr/share/X11/xkb \
        --with-xkb-bin-base=/usr/bin
    make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
    find "$PACKAGE_STAGING" -type f -name '*.la' -delete
    if grep -R -Fq "$EFILINUX_SYSROOT" "$PACKAGE_STAGING"; then
        die "libxklavier embeds the build sysroot"
    fi
    publish_package "$package"
fi

build_release_archive \
    "dbus-glib-$DBUS_GLIB_VERSION" \
    "dbus-glib-$DBUS_GLIB_VERSION.tar.gz" \
    "$DBUS_GLIB_SHA256" \
    "https://dbus.freedesktop.org/releases/dbus-glib/dbus-glib-$DBUS_GLIB_VERSION.tar.gz" \
    --disable-gtk-doc \
    --disable-tests

build_meson_archive \
    "vte-$VTE_VERSION" \
    "vte-$VTE_VERSION.tar.xz" \
    "$VTE_SHA256" \
    "https://download.gnome.org/sources/vte/${VTE_VERSION%.*}/vte-$VTE_VERSION.tar.xz" \
    -Da11y=true \
    -Ddebugg=false \
    -Ddocs=false \
    -Dgir=false \
    -Dfribidi=true \
    -Dglade=false \
    -Dgnutls=false \
    -Dgtk3=true \
    -Dgtk4=false \
    -Dicu=false \
    -D_systemd=false \
    -Dvapi=false
