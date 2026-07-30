#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xorg
pkgver=2025.1

depends=(fontconfig freetype glibc libpng util-linux)
builddepends=()
makedepends=(autoreconf gcc g++ make meson ninja pkg-config python3)

xorg_input() {
    local name=$1 version=$2 checksum_value=$3 url=$4
    local archive="$downloaddir/$name-$version.source"
    download "$url" "$archive"
    checksum sha256 "$checksum_value" "$archive"
    extract "$archive" "$srcdir/$name"
}

prepare() {

    xorg_input 'util-macros' '1.20.2' 'beac7e00e5996bd0c9d9bd8cf62704583b22dbe8613bd768626b95fcac955744' 'https://gitlab.freedesktop.org/xorg/util/macros/-/archive/util-macros-1.20.2/macros-util-macros-1.20.2.tar.gz'
    xorg_input 'xorgproto' '2025.1' '473e9d4608d9c1c3f42346746deb06b3e0d440349422d0857ef0989e17d7e03d' 'https://gitlab.freedesktop.org/xorg/proto/xorgproto/-/archive/xorgproto-2025.1/xorgproto-xorgproto-2025.1.tar.gz'
    xorg_input 'xcb-proto' '1.17.0' '479447448281cfb6585ad780f23bd75311af20daf344fb9209c8a87ea77e296a' 'https://gitlab.freedesktop.org/xorg/proto/xcbproto/-/archive/xcb-proto-1.17.0/xcbproto-xcb-proto-1.17.0.tar.gz'
    xorg_input 'xtrans' '1.6.0' '6def23c86de6ff72030b9971ed6ddec24ba9b47344237ab7b5abeb2f044c3332' 'https://gitlab.freedesktop.org/xorg/lib/libxtrans/-/archive/xtrans-1.6.0/libxtrans-xtrans-1.6.0.tar.gz'
    xorg_input 'libXau' '1.0.12' 'af261cc1b3b349cfe7a7899a48b4e4aa257b4d11bf2ea084fb3191df7d15fbe9' 'https://gitlab.freedesktop.org/xorg/lib/libxau/-/archive/libXau-1.0.12/libxau-libXau-1.0.12.tar.gz'
    xorg_input 'libXdmcp' '1.1.5' 'f5e93a7191e4ea2f43482e9c8470c5320e1bb7ee0070b72f97ad2d1141833cd4' 'https://gitlab.freedesktop.org/xorg/lib/libxdmcp/-/archive/libXdmcp-1.1.5/libxdmcp-libXdmcp-1.1.5.tar.gz'
    xorg_input 'libxcb' '1.17.0' '113a6f8f614e037ff03cad218cdcbfe307dfc9d909a842b17276a694476ed639' 'https://gitlab.freedesktop.org/xorg/lib/libxcb/-/archive/libxcb-1.17.0/libxcb-libxcb-1.17.0.tar.gz'
    xorg_input 'libX11' '1.8.13' 'd210291f5cd974e5029cce4bde0fc1b8bfc0ce88b8530ea6ba4b1fcf141506ab' 'https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-1.8.13/libx11-libX11-1.8.13.tar.gz'
    xorg_input 'libXext' '1.3.7' '65a9b1e6256433af0b37b01436b2e4ee4998da73685d9c8fe579af8ec086dcd2' 'https://gitlab.freedesktop.org/xorg/lib/libxext/-/archive/libXext-1.3.7/libxext-libXext-1.3.7.tar.gz'
    xorg_input 'libXfixes' '6.0.2' '1e7dfe2dd0eb2528fc21c2b1db64443b0f41e2ac623809939be6b4008c42ef5a' 'https://gitlab.freedesktop.org/xorg/lib/libxfixes/-/archive/libXfixes-6.0.2/libxfixes-libXfixes-6.0.2.tar.gz'
    xorg_input 'libXrender' '0.9.12' '470559df9e0e4dbc81d5855d3d364a17e12263600a08217232f8b1f6ef3cddbf' 'https://gitlab.freedesktop.org/xorg/lib/libxrender/-/archive/libXrender-0.9.12/libxrender-libXrender-0.9.12.tar.gz'
    xorg_input 'libXrandr' '1.5.5' '33260581aa2291919c06f2e142da164a1bd8365cb9f7710b55fdf9acd0c65762' 'https://gitlab.freedesktop.org/xorg/lib/libxrandr/-/archive/libXrandr-1.5.5/libxrandr-libXrandr-1.5.5.tar.gz'
    xorg_input 'libXi' '1.8.3' 'f494f8718d0e83fdfe92443f83a073a9f831f178ff0aed060c2d1d24ff4728fd' 'https://gitlab.freedesktop.org/xorg/lib/libxi/-/archive/libXi-1.8.3/libxi-libXi-1.8.3.tar.gz'
    xorg_input 'libXtst' '1.2.5' 'df40471202bb02cca1bd83c559da45a0b4e6d4eddfad5d2bdf8e9d16141c9f7f' 'https://gitlab.freedesktop.org/xorg/lib/libxtst/-/archive/libXtst-1.2.5/libxtst-libXtst-1.2.5.tar.gz'
    xorg_input 'libXcursor' '1.2.3' '840292e5cdfae8d8b795ba00bcbe620a0de0af6ae1847e142df09dec86a70edc' 'https://gitlab.freedesktop.org/xorg/lib/libxcursor/-/archive/libXcursor-1.2.3/libxcursor-libXcursor-1.2.3.tar.gz'
    xorg_input 'libXdamage' '1.1.7' 'a95ca19816ef3751464eb1ad6221e88c51b125c0a2e2836914ce015b05ca0de4' 'https://gitlab.freedesktop.org/xorg/lib/libxdamage/-/archive/libXdamage-1.1.7/libxdamage-libXdamage-1.1.7.tar.gz'
    xorg_input 'libXcomposite' '0.4.7' '61b3608697abb4f3fa80782423b924d26aea77f8e66084658b26196572195dab' 'https://gitlab.freedesktop.org/xorg/lib/libxcomposite/-/archive/libXcomposite-0.4.7/libxcomposite-libXcomposite-0.4.7.tar.gz'
    xorg_input 'libXinerama' '1.1.6' '352475b465d5282eca122877a6e6c3c65be49dccc9dc0200b5eb0f049e924aa6' 'https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/archive/libXinerama-1.1.6/libxinerama-libXinerama-1.1.6.tar.gz'
    xorg_input 'libxshmfence' '1.3.3' '61b90057e1cb1ec4688b2fd223f5008d637ab5a5e476ef3727543bb449c87697' 'https://gitlab.freedesktop.org/xorg/lib/libxshmfence/-/archive/libxshmfence-1.3.3/libxshmfence-libxshmfence-1.3.3.tar.gz'
    xorg_input 'libXxf86vm' '1.1.6' 'a23745e7865f4aa2ee2610f289ed8081140580cbe577b46aa1a7fb28ab7192cf' 'https://gitlab.freedesktop.org/xorg/lib/libxxf86vm/-/archive/libXxf86vm-1.1.6/libxxf86vm-libXxf86vm-1.1.6.tar.gz'
    xorg_input 'libICE' '1.1.2' '575033e22a1190311c1bcf35a994544e38c3394871801ece4610a8ea1438571c' 'https://gitlab.freedesktop.org/xorg/lib/libice/-/archive/libICE-1.1.2/libice-libICE-1.1.2.tar.gz'
    xorg_input 'libSM' '1.2.6' 'f327c29c5d0188f08c9a646999dba3697489470bd04257e22e4bd472d3ee7d6c' 'https://gitlab.freedesktop.org/xorg/lib/libsm/-/archive/libSM-1.2.6/libsm-libSM-1.2.6.tar.gz'
    xorg_input 'libXt' '1.3.1' '07f71c105a979fe570e5b985dfc58ad512973aaa923c29f11b5009c302f9a76e' 'https://gitlab.freedesktop.org/xorg/lib/libxt/-/archive/libXt-1.3.1/libxt-libXt-1.3.1.tar.gz'
    xorg_input 'libXmu' '1.3.1' 'a38bff41f609e2ea887c05fb4a31e926a03ba1d69ddda9423682e198839f2355' 'https://gitlab.freedesktop.org/xorg/lib/libxmu/-/archive/libXmu-1.3.1/libxmu-libXmu-1.3.1.tar.gz'
    xorg_input 'font-util' '1.4.2' 'bf8505b74d0159cd11aeaad929d0e262ebb97eacc09eee7665300cf68f8705e5' 'https://gitlab.freedesktop.org/xorg/font/util/-/archive/font-util-1.4.2/util-font-util-1.4.2.tar.gz'
    xorg_input 'libfontenc' '1.1.8' '31dc201284fb5d2bec60b2ceee3126b5cf633c3de74151be44817890e8e7c581' 'https://gitlab.freedesktop.org/xorg/lib/libfontenc/-/archive/libfontenc-1.1.8/libfontenc-libfontenc-1.1.8.tar.gz'
    xorg_input 'libXfont2' '2.0.8' '033b272a423abd072ec1c51dff8b99b1855c5397fb0b99042b37729df2241c2f' 'https://gitlab.freedesktop.org/xorg/lib/libxfont/-/archive/libXfont2-2.0.8/libxfont-libXfont2-2.0.8.tar.gz'
    xorg_input 'libxkbfile' '1.2.0' '2563c5de4b401c7715af44a3ca4123246a6f6f3b2f99e3bd775761558accf155' 'https://gitlab.freedesktop.org/xorg/lib/libxkbfile/-/archive/libxkbfile-1.2.0/libxkbfile-libxkbfile-1.2.0.tar.gz'
    xorg_input 'libxcvt' '0.1.3' '5edaa65f5abd94ae12030b52fda66828eb8a41396aa9c02fd2c6210445fff61e' 'https://gitlab.freedesktop.org/xorg/lib/libxcvt/-/archive/libxcvt-0.1.3/libxcvt-libxcvt-0.1.3.tar.gz'
    xorg_input 'xkbcomp' '1.5.0' 'b13b443da04ce030adf869cacfe038e04c46eaa9cc61014502dd8fe2c5e4b811' 'https://gitlab.freedesktop.org/xorg/app/xkbcomp/-/archive/xkbcomp-1.5.0/xkbcomp-xkbcomp-1.5.0.tar.gz'
    xorg_input 'libXft' '2.3.9' '7b3affde56c4368d8d673b11871362c1b07052b41858e09139c8b95485356f7b' 'https://gitlab.freedesktop.org/xorg/lib/libxft/-/archive/libXft-2.3.9/libxft-libXft-2.3.9.tar.gz'
    xorg_input 'xcb-util' '0.4.1' '5abe3bbbd8e54f0fa3ec945291b7e8fa8cfd3cccc43718f8758430f94126e512' 'https://xcb.freedesktop.org/dist/xcb-util-0.4.1.tar.xz'
    xorg_input 'libXres' '1.2.2' '651e5d131ebcd8dbe72eccc84f4fbfc754abc02fe825301db2f38102715be25b' 'https://gitlab.freedesktop.org/xorg/lib/libxres/-/archive/libXres-1.2.2/libxres-libXres-1.2.2.tar.gz'
    xorg_input 'libXpresent' '1.0.1' '3ea271a49d798280fdceb746658b7d7b9f34340db15b993c827eebc0abc96285' 'https://gitlab.freedesktop.org/xorg/lib/libxpresent/-/archive/libXpresent-1.0.1/libxpresent-libXpresent-1.0.1.tar.gz'
    xorg_input 'libXScrnSaver' '1.2.5' '127cd6862cfe7bcd14aa882e82695b3ca2b05e0cc9c208cadbbfb0f6a1114734' 'https://gitlab.freedesktop.org/xorg/lib/libxscrnsaver/-/archive/libXScrnSaver-1.2.5/libxscrnsaver-libXScrnSaver-1.2.5.tar.gz'
    xorg_input 'xauth' '1.1.5' 'f14be76a7f0fe575e354920648d802caef714765a5dd512fefaad206d9c47508' 'https://gitlab.freedesktop.org/xorg/app/xauth/-/archive/xauth-1.1.5/xauth-xauth-1.1.5.tar.gz'
    xorg_input 'iceauth' '1.0.11' 'eeb5dce19592b3e0b2c68dcd8fe88289f47ea769fb6216c64a84fabab3294693' 'https://gitlab.freedesktop.org/xorg/app/iceauth/-/archive/iceauth-1.0.11/iceauth-iceauth-1.0.11.tar.gz'
    xorg_input 'xinit' '1.4.4' 'a0efb773acea51c35e1295bfc1ac957ddf1edede9f76c20929e9c13b0644eb7a' 'https://gitlab.freedesktop.org/xorg/app/xinit/-/archive/xinit-1.4.4/xinit-xinit-1.4.4.tar.gz'
    xorg_input 'xwininfo' '1.1.7' 'fab29247293e5e3d391f903eef6a7c60c2b9d445eb5d14d1c500de6885856491' 'https://gitlab.freedesktop.org/xorg/app/xwininfo/-/archive/xwininfo-1.1.7/xwininfo-xwininfo-1.1.7.tar.gz'
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}


xorg_merge_stage() {
    local stage=$1
    cp -a --reflink=auto "$stage/." "$develdir/"
    cp -a --reflink=auto "$stage/." "$EFILINUX_SYSROOT/"
}

xorg_build_autotools() {
    local name=$1
    shift
    local component_build="$builddir/components/$name"
    local component_stage="$builddir/stages/$name"
    reset_directory "$component_build"
    reset_directory "$component_stage"
    target_autotools_configure "$srcdir/$name" "$component_build" "$@"
    target_make_install "$component_build" "$component_stage"
    if [[ $name == xorgproto ]]; then
        rm -f             "$component_stage/usr/include/X11/extensions/xwaylandproto.h"             "$component_stage/usr/share/pkgconfig/xwaylandproto.pc"             "$component_stage/usr/share/doc/xorgproto/xwaylandproto.txt"
    fi
    xorg_merge_stage "$component_stage"
}

xorg_build_meson() {
    local name=$1
    shift
    local component_build="$builddir/components/$name"
    local component_stage="$builddir/stages/$name"
    reset_directory "$component_build"
    reset_directory "$component_stage"
    target_meson_setup "$srcdir/$name" "$component_build" "$@"
    target_meson_install "$component_build" "$component_stage"
    xorg_merge_stage "$component_stage"
}

build() {
    local original_sysroot=$EFILINUX_SYSROOT
    local internal_sysroot="$builddir/sysroot"
    reset_directory "$internal_sysroot"
    cp -a --reflink=auto "$original_sysroot/." "$internal_sysroot/"
    target_rebind_sysroot "$internal_sysroot"
    mkdir -p "$develdir"

    xorg_build_autotools 'util-macros'
    xorg_build_autotools 'xorgproto' '--without-fop' '--without-xmlto'
    xorg_build_autotools 'xcb-proto'
    xorg_build_autotools 'xtrans'
    xorg_build_autotools 'libXau' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXdmcp' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libxcb' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libX11' '--disable-static' '--disable-docs' '--disable-xf86bigfont'
    xorg_build_autotools 'libXext' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXfixes' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXrender' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXrandr' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXi' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXtst' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXcursor' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXdamage' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXcomposite' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXinerama' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libxshmfence' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXxf86vm' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libICE' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libSM' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXt' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXmu' '--disable-static' '--disable-docs'
    xorg_build_autotools 'font-util' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libfontenc' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXfont2' '--disable-static' '--disable-docs'
    xorg_build_meson 'libxkbfile'
    xorg_build_meson 'libxcvt'
    xorg_build_meson 'xkbcomp' '-Dxkb-config-root=/usr/share/X11/xkb'
    xorg_build_meson 'libXft'
    xorg_build_autotools 'xcb-util' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXres' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXpresent' '--disable-static' '--disable-docs'
    xorg_build_autotools 'libXScrnSaver' '--disable-static' '--disable-docs'
    xorg_build_autotools 'xauth' '--disable-static' '--disable-docs'
    xorg_build_autotools 'iceauth' '--disable-static' '--disable-docs'
    xorg_build_autotools 'xinit' '--disable-static' '--disable-docs' '--with-xinitdir=/etc/X11/xinit'
    xorg_build_meson 'xwininfo' '-Dxcb-errors=disabled' '-Dxcb-icccm=disabled'

    target_rebind_sysroot "$original_sysroot"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/xinit
        /usr/bin/startx
        /usr/bin/xkbcomp
        /usr/bin/xwininfo
        /usr/bin/xauth
        /usr/bin/iceauth
        /usr/share/X11/locale/
    )
    package_add_library_family keep 'libX*.so.*'
    package_add_library_family keep 'libxcb*.so.*'
    package_add_library_family keep 'libICE.so.*'
    package_add_library_family keep 'libSM.so.*'
    package_add_library_family keep 'libxshmfence.so.*'
    package_add_library_family keep 'libxkbfile.so.*'
    package_add_library_family keep 'libfontenc.so.*'
    package_add_library_family keep 'libxcvt.so.*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
