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

build_xorg_library() {
    local package_name=$1
    local version=$2
    local sha256=$3
    local project=$4
    local tag=$5
    shift 5
    local archive="$package_name-$tag.tar.gz"
    local package="$package_name-$version"
    local slug=${project##*/}

    graphical_prepare_archive \
        "$package" "$archive" "$sha256" \
        "https://gitlab.freedesktop.org/$project/-/archive/$tag/$slug-$tag.tar.gz"
    graphical_autotools_configure \
        "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static --disable-docs "$@"
    graphical_make_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    merge_sysroot "$PACKAGE_STAGING"
}

build_xorg_library libXau "$LIBXAU_VERSION" "$LIBXAU_SHA256" \
    xorg/lib/libxau "libXau-$LIBXAU_VERSION"
build_xorg_library libXdmcp "$LIBXDMCP_VERSION" "$LIBXDMCP_SHA256" \
    xorg/lib/libxdmcp "libXdmcp-$LIBXDMCP_VERSION"
build_xorg_library libxcb "$LIBXCB_VERSION" "$LIBXCB_SHA256" \
    xorg/lib/libxcb "libxcb-$LIBXCB_VERSION"
build_xorg_library libX11 "$LIBX11_VERSION" "$LIBX11_SHA256" \
    xorg/lib/libx11 "libX11-$LIBX11_VERSION" --disable-xf86bigfont
build_xorg_library libXext "$LIBXEXT_VERSION" "$LIBXEXT_SHA256" \
    xorg/lib/libxext "libXext-$LIBXEXT_VERSION"
build_xorg_library libXfixes "$LIBXFIXES_VERSION" "$LIBXFIXES_SHA256" \
    xorg/lib/libxfixes "libXfixes-$LIBXFIXES_VERSION"
build_xorg_library libXrender "$LIBXRENDER_VERSION" "$LIBXRENDER_SHA256" \
    xorg/lib/libxrender "libXrender-$LIBXRENDER_VERSION"
build_xorg_library libXrandr "$LIBXRANDR_VERSION" "$LIBXRANDR_SHA256" \
    xorg/lib/libxrandr "libXrandr-$LIBXRANDR_VERSION"
build_xorg_library libXi "$LIBXI_VERSION" "$LIBXI_SHA256" \
    xorg/lib/libxi "libXi-$LIBXI_VERSION"
build_xorg_library libXcursor "$LIBXCURSOR_VERSION" "$LIBXCURSOR_SHA256" \
    xorg/lib/libxcursor "libXcursor-$LIBXCURSOR_VERSION"
build_xorg_library libXdamage "$LIBXDAMAGE_VERSION" "$LIBXDAMAGE_SHA256" \
    xorg/lib/libxdamage "libXdamage-$LIBXDAMAGE_VERSION"
build_xorg_library libXcomposite "$LIBXCOMPOSITE_VERSION" "$LIBXCOMPOSITE_SHA256" \
    xorg/lib/libxcomposite "libXcomposite-$LIBXCOMPOSITE_VERSION"
build_xorg_library libXinerama "$LIBXINERAMA_VERSION" "$LIBXINERAMA_SHA256" \
    xorg/lib/libxinerama "libXinerama-$LIBXINERAMA_VERSION"
build_xorg_library libxshmfence "$LIBXSHMFENCE_VERSION" "$LIBXSHMFENCE_SHA256" \
    xorg/lib/libxshmfence "libxshmfence-$LIBXSHMFENCE_VERSION"
build_xorg_library libXxf86vm "$LIBXXF86VM_VERSION" "$LIBXXF86VM_SHA256" \
    xorg/lib/libxxf86vm "libXxf86vm-$LIBXXF86VM_VERSION"
