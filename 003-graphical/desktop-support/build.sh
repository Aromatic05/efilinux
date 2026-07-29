#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/003-graphical/desktop-support/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command autoreconf curl find gcc make meson ninja pkg-config sha256sum tar
ensure_directories

recipe_inputs=(
    "$ROOT/001-runtime/config.sh"
    "$ROOT/002-system/desktop-config.sh"
    "$ROOT/003-graphical/config.sh"
    "$ROOT/003-graphical/desktop-support/config.sh"
    "$ROOT/003-graphical/lib/build.sh"
)

restore_package() {
    local package=$1
    binary_package_restore_sysroot \
        "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

publish_package() {
    local package=$1
    binary_package_publish_sysroot \
        "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

prune_translations() {
    local staging=$1
    local locale_directory="$staging/usr/share/locale"
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
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    restore_package "$package" && return
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_autotools_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --disable-silent-rules \
        "$@"
    make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
    publish_package "$package"
}

build_release_archive() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    restore_package "$package" && return
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_release_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --disable-silent-rules \
        "$@"
    make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    prune_translations "$PACKAGE_STAGING"
    publish_package "$package"
}

build_meson_archive() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
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

build_release_archive \
    "xcb-util-$XCB_UTIL_VERSION" \
    "xcb-util-$XCB_UTIL_VERSION.tar.xz" \
    "$XCB_UTIL_SHA256" \
    "https://xcb.freedesktop.org/dist/xcb-util-$XCB_UTIL_VERSION.tar.xz"

build_autotools_snapshot \
    "libXres-$LIBXRES_VERSION" \
    "libXres-$LIBXRES_VERSION.tar.gz" \
    "$LIBXRES_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxres/-/archive/libXres-$LIBXRES_VERSION/libxres-libXres-$LIBXRES_VERSION.tar.gz"

build_autotools_snapshot \
    "libXpresent-$LIBXPRESENT_VERSION" \
    "libXpresent-$LIBXPRESENT_VERSION.tar.gz" \
    "$LIBXPRESENT_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxpresent/-/archive/libXpresent-$LIBXPRESENT_VERSION/libxpresent-libXpresent-$LIBXPRESENT_VERSION.tar.gz"

build_autotools_snapshot \
    "startup-notification-$STARTUP_NOTIFICATION_VERSION" \
    "startup-notification-STARTUP_NOTIFICATION_0_12.tar.gz" \
    "$STARTUP_NOTIFICATION_SHA256" \
    "https://gitlab.freedesktop.org/xdg/startup-notification/-/archive/STARTUP_NOTIFICATION_0_12/startup-notification-STARTUP_NOTIFICATION_0_12.tar.gz"

build_meson_archive \
    "libnotify-$LIBNOTIFY_VERSION" \
    "libnotify-$LIBNOTIFY_VERSION.tar.xz" \
    "$LIBNOTIFY_SHA256" \
    "https://download.gnome.org/sources/libnotify/${LIBNOTIFY_VERSION%.*}/libnotify-$LIBNOTIFY_VERSION.tar.xz" \
    -Dtests=false \
    -Dintrospection=disabled \
    -Dman=false \
    -Dgtk_doc=false \
    -Ddocbook_docs=disabled

build_meson_archive \
    "libwnck-$LIBWNCK_VERSION" \
    "libwnck-$LIBWNCK_VERSION.tar.xz" \
    "$LIBWNCK_SHA256" \
    "https://download.gnome.org/sources/libwnck/${LIBWNCK_VERSION%%.*}/libwnck-$LIBWNCK_VERSION.tar.xz" \
    -Dstartup_notification=enabled \
    -Dintrospection=disabled \
    -Dgtk_doc=false \
    -Dinstall_tools=false
