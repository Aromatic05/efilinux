#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command autoreconf curl gcc make pkg-config sha256sum tar
ensure_directories

build_xorg_component() {
    local package_name=$1
    local version=$2
    local sha256=$3
    local project=$4
    shift 4
    local tag="$package_name-$version"
    local archive="$package_name-$tag.tar.gz"
    local package="$package_name-$version"
    local slug=${project##*/}

    if graphical_binary_package_restore "$package"; then
        return
    fi
    graphical_prepare_archive \
        "$package" "$archive" "$sha256" \
        "https://gitlab.freedesktop.org/$project/-/archive/$tag/$slug-$tag.tar.gz"
    graphical_autotools_configure \
        "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    graphical_make_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
}

build_xorg_component libICE "$LIBICE_VERSION" "$LIBICE_SHA256" xorg/lib/libice \
    --disable-static --disable-docs
build_xorg_component libSM "$LIBSM_VERSION" "$LIBSM_SHA256" xorg/lib/libsm \
    --disable-static --disable-docs
build_xorg_component libXt "$LIBXT_VERSION" "$LIBXT_SHA256" xorg/lib/libxt \
    --disable-static --disable-docs
build_xorg_component libXmu "$LIBXMU_VERSION" "$LIBXMU_SHA256" xorg/lib/libxmu \
    --disable-static --disable-docs
build_xorg_component xauth "$XAUTH_VERSION" "$XAUTH_SHA256" xorg/app/xauth

for dependency in ice sm xt xmu; do
    target_pkg_config --exists "$dependency" || \
        die "X11 session dependency is missing: $dependency"
done

for artifact in \
    usr/lib/libICE.so.6 \
    usr/lib/libSM.so.6 \
    usr/lib/libXt.so.6 \
    usr/lib/libXmu.so.6 \
    usr/bin/xauth; do
    [[ -e "$EFILINUX_SYSROOT/$artifact" ]] || \
        die "X11 session artifact is missing: /$artifact"
done
