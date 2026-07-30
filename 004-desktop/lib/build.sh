#!/usr/bin/env bash

set -euo pipefail

DESKTOP_RECIPE_INPUTS=(
    "$ROOT/002-system/desktop-config.sh"
    "$ROOT/003-graphical/config.sh"
    "$ROOT/003-graphical/desktop-support/config.sh"
    "$ROOT/003-graphical/lib/build.sh"
    "$ROOT/004-desktop/config.sh"
    "$ROOT/004-desktop/lib/build.sh"
)

desktop_package_restore() {
    local package=$1
    local producer=$2
    binary_package_restore_sysroot \
        "$package" "$producer" "${DESKTOP_RECIPE_INPUTS[@]}"
}

desktop_package_publish() {
    local package=$1
    local producer=$2
    binary_package_publish_sysroot \
        "$package" "$producer" "${DESKTOP_RECIPE_INPUTS[@]}"
}

desktop_prune_translations() {
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

desktop_release_build() {
    local component=$1
    local version=$2
    local sha256=$3
    local producer=$4
    shift 4

    local package="$component-$version"
    local archive="$component-$version.tar.bz2"

    desktop_package_restore "$package" "$producer" && return 0
    graphical_prepare_archive \
        "$package" \
        "$archive" \
        "$sha256" \
        "https://archive.xfce.org/src/xfce/$component/4.18/$archive"
    graphical_release_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static \
        --disable-silent-rules \
        --sysconfdir=/etc \
        "$@"
    env -u LD_LIBRARY_PATH make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
    env -u LD_LIBRARY_PATH make -C "$PACKAGE_BUILD" \
        DESTDIR="$PACKAGE_STAGING" install
    find "$PACKAGE_STAGING" -type f -name '*.la' -delete 2>/dev/null || true
    graphical_normalize_pkg_config "$PACKAGE_STAGING"
    desktop_prune_translations "$PACKAGE_STAGING"
    desktop_package_publish "$package" "$producer"
}
