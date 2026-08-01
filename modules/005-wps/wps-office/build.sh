#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=wps-office
pkgver=10.1.0.5672~a21
depends=(libpng12)
builddepends=()
makedepends=(curl dpkg-deb find readelf sha1sum)
sysroot=false

readonly wps_deb_name='wps-office_10.1.0.5672~a21_amd64.deb'
# Public mirror of the original a21 amd64 file; the upstream kdl.cc.ksosoft.com
# endpoint is no longer available.  Do not substitute another WPS build.
readonly wps_share_url='https://app.box.com/s/f5pp05570oq9j4jac6r35xzgy35g42ww'
readonly wps_deb_url='https://app.box.com/shared/static/f5pp05570oq9j4jac6r35xzgy35g42ww.deb'
readonly wps_deb_sha1='80d884c47eaeee3305958ed87e61eafbee30b0cf'

wps_source() {
    local archive="$downloaddir/$wps_deb_name"
    local cookie_jar="$srcdir/box.cookies"
    local landing="$srcdir/box-share.html"

    RECIPE_INPUT_RECORDS+=("download=$wps_deb_url|$wps_deb_name")
    RECIPE_INPUT_RECORDS+=("checksum=sha1|$wps_deb_sha1|$wps_deb_name")
    if [[ "$RECIPE_INPUT_MODE" == metadata ]]; then
        printf '%s' "$archive"
        return
    fi

    if [[ ! -f "$archive" ]]; then
        mkdir -p "$downloaddir" "$srcdir"
        curl -L --fail --retry 5 --retry-delay 2 --retry-all-errors \
            --silent --show-error \
            -A 'Mozilla/5.0' \
            -c "$cookie_jar" \
            "$wps_share_url" \
            -o "$landing"
        curl -L --fail --retry 5 --retry-delay 2 --retry-all-errors \
            --silent --show-error \
            -A 'Mozilla/5.0' \
            -b "$cookie_jar" \
            -c "$cookie_jar" \
            -e "$wps_share_url" \
            "$wps_deb_url" \
            -o "$archive"
    fi
    if [[ ! -f "$archive" ]]; then
        die "required WPS source is unavailable: $archive (download: $wps_deb_url)"
    fi
    printf '%s' "$archive"
}

wps_verify_source() {
    local archive=$1

    [[ $(sha1sum "$archive" | awk '{print $1}') == "$wps_deb_sha1" ]] ||
        die "WPS a21 source checksum mismatch: $archive"
    [[ $(dpkg-deb --field "$archive" Package) == wps-office ]] ||
        die "WPS source has an unexpected package name: $archive"
    [[ $(dpkg-deb --field "$archive" Version) == "$pkgver" ]] ||
        die "WPS source has an unexpected package version: $archive"
    [[ $(dpkg-deb --field "$archive" Architecture) == amd64 ]] ||
        die "WPS source has an unexpected architecture: $archive"
}

wps_prune_locales() {
    local directory locale

    for directory in \
        "$develdir/opt/kingsoft/wps-office/office6/mui" \
        "$develdir/opt/kingsoft/wps-office/office6/resource/locale"; do
        [[ -d "$directory" ]] || continue
        while IFS= read -r -d '' locale; do
            case $(basename -- "$locale") in
                en_US|zh_CN) ;;
                *) rm -rf -- "$locale" ;;
            esac
        done < <(find "$directory" -mindepth 1 -maxdepth 1 -type d -print0)
    done
}

wps_base_replaces_library() {
    local bundled=$1 soname base versions

    soname=$(readelf -d "$bundled" 2>/dev/null |
        sed -n 's/.*SONAME.*\[\(.*\)\]/\1/p' | head -n 1)
    [[ -n "$soname" && -e "$EFILINUX_ROOTFS/usr/lib/$soname" ]] || return 1
    base="$EFILINUX_ROOTFS/usr/lib/$soname"
    # A matching SONAME is only accepted when the base exports every versioned
    # ABI advertised by the bundled library.  Unversioned libraries stay local.
    versions=$(readelf --version-info "$bundled" 2>/dev/null |
        sed -n 's/.*Name: \([^ ]*\).*/\1/p' | LC_ALL=C sort -u)
    [[ -n "$versions" ]] || return 1
    while IFS= read -r version; do
        grep -Fqx "$version" < <(
            readelf --version-info "$base" 2>/dev/null |
                sed -n 's/.*Name: \([^ ]*\).*/\1/p' | LC_ALL=C sort -u
        ) || return 1
    done <<<"$versions"
}

wps_prune_replaced_libraries() {
    local library target

    while IFS= read -r -d '' library; do
        [[ ! -L "$library" ]] || continue
        wps_base_replaces_library "$library" || continue
        target=$(readlink -f -- "$library")
        rm -f -- "$library"
        find "$(dirname -- "$target")" -maxdepth 1 -type l \
            -lname "$(basename -- "$target")" -delete
        rm -f -- "$target"
    done < <(find "$develdir/opt/kingsoft/wps-office/office6" -type f \
        -name '*.so*' -print0 | LC_ALL=C sort -z)
}

build() {
    dpkg-deb --extract "$downloaddir/$wps_deb_name" "$srcdir/unpacked"
    cp -a "$srcdir/unpacked/." "$develdir/"

    rm -rf -- \
        "$develdir/usr/share/doc" \
        "$develdir/usr/share/man" \
        "$develdir/usr/include" \
        "$develdir/usr/lib/pkgconfig" \
        "$develdir/opt/kingsoft/wps-office/office6/addons/homepage"
    find "$develdir/opt/kingsoft/wps-office/office6" -type d \
        \( -iname fonts -o -iname templates -o -iname help \) \
        -prune -exec rm -rf -- {} +
    find "$develdir/opt/kingsoft/wps-office" -type f \
        \( -name '*.a' -o -name '*.la' -o -name '*.o' -o -name '*.debug' \) -delete
    find "$develdir/opt/kingsoft/wps-office" -type f \
        \( -iname '*updater*' -o -iname 'wpsupdate*' -o -iname '*crash*' \
           -o -iname '*report*' \) -delete
    find "$develdir/opt/kingsoft/wps-office" -type d \
        \( -iname '*updater*' -o -iname '*crash*' -o -iname '*report*' \) \
        -prune -exec rm -rf -- {} +
    wps_prune_locales
    wps_prune_replaced_libraries
}

prepare() {
    wps_source >/dev/null
    [[ "$RECIPE_INPUT_MODE" == metadata ]] ||
        wps_verify_source "$downloaddir/$wps_deb_name"
}

package() {
    package_keep /usr/bin/ /usr/share/applications/ /usr/share/icons/ /usr/share/mime/ \
        /opt/kingsoft/wps-office/
}

recipe_main "$@"
