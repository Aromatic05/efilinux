#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/001-runtime/desktop-libraries/config.sh"
source "$ROOT/002-system/desktop-services/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories

recipe_inputs=(
    "$ROOT/001-runtime/config.sh"
    "$ROOT/002-system/desktop-services/config.sh"
)

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

meson_target() {
    local source=$1
    shift
    CC=gcc \
    CFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$PACKAGE_BUILD/pkgconfig:$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$source" \
            --prefix=/usr \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            --auto-features=disabled \
            "$@"
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" \
        meson install -C "$PACKAGE_BUILD"
}

package="pulseaudio-$PULSEAUDIO_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$PULSEAUDIO_SHA256" \
        "https://freedesktop.org/software/pulseaudio/releases/$package.tar.xz"
    meson_target "$PACKAGE_SOURCE" \
        -Ddaemon=false \
        -Dclient=true \
        -Ddoxygen=false \
        -Dman=false \
        -Dtests=false \
        -Ddatabase=simple \
        -Dalsa=disabled \
        -Dasyncns=disabled \
        -Davahi=disabled \
        -Dbluez5=disabled \
        -Dconsolekit=disabled \
        -Ddbus=enabled \
        -Delogind=disabled \
        -Dfftw=disabled \
        -Dglib=enabled \
        -Dgsettings=disabled \
        -Dgstreamer=disabled \
        -Dgtk=disabled \
        -Djack=disabled \
        -Dlirc=disabled \
        -Dopenssl=disabled \
        -Dorc=disabled \
        -Doss-output=disabled \
        -Dsamplerate=disabled \
        -Dsoxr=disabled \
        -Dspeex=disabled \
        -Dsystemd=disabled \
        -Dtcpwrap=disabled \
        -Dudev=disabled \
        -Dx11=disabled
    publish_package "$package"
fi

package="pipewire-$PIPEWIRE_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$PIPEWIRE_SHA256" \
        "https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/$PIPEWIRE_VERSION/$package.tar.gz"
    meson_target "$PACKAGE_SOURCE" \
        -Ddocs=disabled \
        -Dman=disabled \
        -Dexamples=disabled \
        -Dtests=disabled \
        -Dsystemd-system-service=disabled \
        -Dsystemd-user-service=disabled \
        -Dselinux=disabled \
        -Dpipewire-alsa=enabled \
        -Dpipewire-jack=disabled \
        -Dalsa=enabled \
        -Dbluez5=disabled \
        -Djack=disabled \
        -Dv4l2=disabled \
        -Ddbus=enabled \
        -Dlibcamera=disabled \
        -Dudev=enabled \
        -Dudevrulesdir=/usr/lib/udev/rules.d \
        -Dsndfile=disabled \
        -Davahi=disabled \
        -Dsession-managers=[] \
        -Dx11=disabled \
        -Dreadline=enabled \
        -Dgsettings=disabled \
        -Dfftw=disabled \
        -Dgstreamer=disabled
    publish_package "$package"
fi

package="wireplumber-$WIREPLUMBER_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$WIREPLUMBER_SHA256" \
        "https://gitlab.freedesktop.org/pipewire/wireplumber/-/archive/$WIREPLUMBER_VERSION/$package.tar.gz"
    mkdir -p "$PACKAGE_BUILD/pkgconfig"
    cp "$EFILINUX_SYSROOT/usr/lib/pkgconfig/lua.pc" \
        "$PACKAGE_BUILD/pkgconfig/lua-5.4.pc"
    cp "$EFILINUX_SYSROOT/usr/lib/pkgconfig/lua.pc" \
        "$PACKAGE_BUILD/pkgconfig/lua5.4.pc"
    meson_target "$PACKAGE_SOURCE" \
        -Dintrospection=disabled \
        -Ddoc=disabled \
        -Dmodules=true \
        -Ddaemon=true \
        -Dtools=true \
        -Dsystem-lua=true \
        -Dsystem-lua-version=5.4 \
        -Delogind=enabled \
        -Dsystemd=disabled \
        -Dsystemd-system-service=false \
        -Dsystemd-user-service=false \
        -Dtests=false \
        -Ddbus-tests=false
    publish_package "$package"
fi
