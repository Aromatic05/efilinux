#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/003-graphical/desktop-support/config.sh"
source "$ROOT/003-graphical/session-support/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command find glib-compile-schemas python3 readelf sed sha256sum strip tar
ensure_directories

files_root="$ROOT/003-graphical/graphical-rootfs/files"
assembly="$EFILINUX_BUILD/assembly/graphical-rootfs"
reset_directory "$assembly"
package_materialization="$assembly/packages"
mkdir -p "$package_materialization"

stage() {
    local package=$1
    local directory="$package_materialization/$package"

    if [[ ! -d "$directory" ]]; then
        binary_package_materialize "$package" "$directory"
    fi
    printf '%s' "$directory"
}

install_stage_program() {
    local owner=$1
    local package=$2
    local program=$3
    local name=${4:-$program}

    install_rootfs_program \
        "$owner" "$(stage "$package")/usr/bin/$program" "$name"
}

install_stage_libraries() {
    local owner=$1
    local package=$2
    local directory
    local source
    local libraries=()

    directory=$(stage "$package")
    shopt -s nullglob
    libraries=("$directory/usr/lib/"*.so*)
    shopt -u nullglob
    ((${#libraries[@]} > 0)) || \
        die "graphical shared libraries are missing: $package"

    for source in "${libraries[@]}"; do
        install_rootfs_file \
            "$owner" "$source" "/usr/lib/$(basename -- "$source")"
    done
}

log "Installing graphical shared-library closure"
while read -r owner package; do
    [[ -n "$owner" ]] || continue
    install_stage_libraries "$owner" "$package"
done <<EOF
llvm llvm-$LLVM_VERSION
libpciaccess libpciaccess-$LIBPCIACCESS_VERSION
libdrm libdrm-$LIBDRM_VERSION
elfutils elfutils-$ELFUTILS_VERSION
mesa mesa-$MESA_VERSION
libevdev libevdev-$LIBEVDEV_VERSION
libinput libinput-$LIBINPUT_VERSION
libxkbcommon libxkbcommon-$LIBXKBCOMMON_VERSION
libpng libpng-$LIBPNG_VERSION
libjpeg libjpeg-turbo-$LIBJPEG_TURBO_VERSION
freetype freetype-$FREETYPE_VERSION
fontconfig fontconfig-$FONTCONFIG_VERSION
harfbuzz harfbuzz-$HARFBUZZ_VERSION
fribidi fribidi-$FRIBIDI_VERSION
pixman pixman-$PIXMAN_VERSION
libXau libXau-$LIBXAU_VERSION
libXdmcp libXdmcp-$LIBXDMCP_VERSION
libxcb libxcb-$LIBXCB_VERSION
libX11 libX11-$LIBX11_VERSION
libXext libXext-$LIBXEXT_VERSION
libXfixes libXfixes-$LIBXFIXES_VERSION
libXrender libXrender-$LIBXRENDER_VERSION
libXrandr libXrandr-$LIBXRANDR_VERSION
libXi libXi-$LIBXI_VERSION
libXtst libXtst-$LIBXTST_VERSION
libXcursor libXcursor-$LIBXCURSOR_VERSION
libXdamage libXdamage-$LIBXDAMAGE_VERSION
libXcomposite libXcomposite-$LIBXCOMPOSITE_VERSION
libXinerama libXinerama-$LIBXINERAMA_VERSION
libxshmfence libxshmfence-$LIBXSHMFENCE_VERSION
libXxf86vm libXxf86vm-$LIBXXF86VM_VERSION
libepoxy libepoxy-$LIBEPOXY_VERSION
libXft libXft-$LIBXFT_VERSION
libfontenc libfontenc-$LIBFONTENC_VERSION
libXfont2 libXfont2-$LIBXFONT2_VERSION
libxkbfile libxkbfile-$LIBXKBFILE_VERSION
libxcvt libxcvt-$LIBXCVT_VERSION
libxml2 libxml2-$LIBXML2_VERSION
at-spi2 at-spi2-core-$AT_SPI2_CORE_VERSION
gdk-pixbuf gdk-pixbuf-$GDK_PIXBUF_VERSION
cairo cairo-$CAIRO_VERSION
pango pango-$PANGO_VERSION
gtk3 gtk-$GTK3_VERSION
libICE libICE-$LIBICE_VERSION
libSM libSM-$LIBSM_VERSION
libXt libXt-$LIBXT_VERSION
libXmu libXmu-$LIBXMU_VERSION
xcb-util xcb-util-$XCB_UTIL_VERSION
libXres libXres-$LIBXRES_VERSION
libXpresent libXpresent-$LIBXPRESENT_VERSION
startup-notification startup-notification-$STARTUP_NOTIFICATION_VERSION
libnotify libnotify-$LIBNOTIFY_VERSION
libwnck libwnck-$LIBWNCK_VERSION
libXss libXScrnSaver-$LIBXSS_VERSION
libxklavier libxklavier-$LIBXKLAVIER_VERSION
dbus-glib dbus-glib-$DBUS_GLIB_VERSION
vte vte-$VTE_VERSION
EOF

log "Installing Xorg and GTK session programs"
install_stage_program xorg-server "xorg-server-$XORG_SERVER_VERSION" Xorg
install_stage_program xorg-server "xorg-server-$XORG_SERVER_VERSION" X
install_rootfs_file xorg-server \
    "$(stage "xorg-server-$XORG_SERVER_VERSION")/usr/libexec/Xorg" \
    /usr/libexec/Xorg
install_rootfs_file xorg-server \
    "$(stage "xorg-server-$XORG_SERVER_VERSION")/usr/libexec/Xorg.wrap" \
    /usr/libexec/Xorg.wrap
install_stage_program xinit "xinit-$XINIT_VERSION" xinit
install_stage_program xinit "xinit-$XINIT_VERSION" startx
install_stage_program xkbcomp "xkbcomp-$XKBCOMP_VERSION" xkbcomp
install_stage_program xwininfo "xwininfo-$XWININFO_VERSION" xwininfo
install_stage_program xauth "xauth-$XAUTH_VERSION" xauth
install_stage_program iceauth "iceauth-$ICEAUTH_VERSION" iceauth
install_stage_program util-linux "util-linux-$UTIL_LINUX_VERSION" mcookie
install_stage_program gtk3 "gtk-$GTK3_VERSION" gtk3-demo
install_stage_program gtk3 "gtk-$GTK3_VERSION" gtk3-widget-factory
install_stage_program fontconfig "fontconfig-$FONTCONFIG_VERSION" fc-cache
install_stage_program fontconfig "fontconfig-$FONTCONFIG_VERSION" fc-match
if [[ -d "$(stage "vte-$VTE_VERSION")/usr/libexec" ]]; then
    install_rootfs_tree vte \
        "$(stage "vte-$VTE_VERSION")/usr/libexec" /usr/libexec
fi
if [[ -d "$(stage "vte-$VTE_VERSION")/usr/share/vte" ]]; then
    install_rootfs_tree vte \
        "$(stage "vte-$VTE_VERSION")/usr/share/vte" /usr/share/vte
fi

log "Installing graphics drivers, input data, fonts, and toolkit resources"
install_rootfs_tree mesa \
    "$(stage "mesa-$MESA_VERSION")/usr/lib/dri" /usr/lib/dri
install_rootfs_tree mesa \
    "$(stage "mesa-$MESA_VERSION")/usr/lib/gbm" /usr/lib/gbm
install_rootfs_tree mesa \
    "$(stage "mesa-$MESA_VERSION")/usr/share/drirc.d" /usr/share/drirc.d
install_rootfs_tree libdrm \
    "$(stage "libdrm-$LIBDRM_VERSION")/usr/share/libdrm" /usr/share/libdrm

install_rootfs_tree xorg-server \
    "$(stage "xorg-server-$XORG_SERVER_VERSION")/usr/lib/xorg" /usr/lib/xorg
install_rootfs_tree xf86-input-libinput \
    "$(stage "xf86-input-libinput-$XF86_INPUT_LIBINPUT_VERSION")/usr/lib/xorg" /usr/lib/xorg
install_rootfs_tree xf86-video-fbdev \
    "$(stage "xf86-video-fbdev-$XF86_VIDEO_FBDEV_VERSION")/usr/lib/xorg" /usr/lib/xorg
install_rootfs_tree xorg-server \
    "$(stage "xorg-server-$XORG_SERVER_VERSION")/usr/share/X11/xorg.conf.d" \
    /usr/share/X11/xorg.conf.d
install_rootfs_tree xf86-input-libinput \
    "$(stage "xf86-input-libinput-$XF86_INPUT_LIBINPUT_VERSION")/usr/share/X11/xorg.conf.d" \
    /usr/share/X11/xorg.conf.d
install_rootfs_tree libX11 \
    "$(stage "libX11-$LIBX11_VERSION")/usr/share/X11/locale" /usr/share/X11/locale
install_rootfs_tree xkeyboard-config \
    "$(stage "xkeyboard-config-$XKEYBOARD_CONFIG_VERSION")/usr/share/xkeyboard-config-2" \
    /usr/share/xkeyboard-config-2
install_rootfs_symlink \
    xkeyboard-config ../xkeyboard-config-2 /usr/share/X11/xkb
install_rootfs_tree libinput \
    "$(stage "libinput-$LIBINPUT_VERSION")/usr/share/libinput" /usr/share/libinput
install_rootfs_tree libinput \
    "$(stage "libinput-$LIBINPUT_VERSION")/usr/lib/udev" /usr/lib/udev

install_rootfs_tree fontconfig \
    "$(stage "fontconfig-$FONTCONFIG_VERSION")/etc/fonts" /etc/fonts
install_rootfs_tree fontconfig \
    "$(stage "fontconfig-$FONTCONFIG_VERSION")/usr/share/fontconfig" \
    /usr/share/fontconfig
install_rootfs_tree dejavu-fonts \
    "$(stage "dejavu-fonts-$DEJAVU_FONTS_VERSION")/usr/share/fonts" /usr/share/fonts
install_rootfs_tree noto-sans-cjk-sc \
    "$(stage "noto-sans-cjk-sc-$NOTO_SANS_CJK_VERSION")/usr/share/fonts" \
    /usr/share/fonts
install_new_rootfs_tree qogir-icon-theme \
    "$(stage "qogir-icon-theme-$QOGIR_ICON_VERSION")/usr/share/icons/Qogir" \
    /usr/share/icons/Qogir
install_rootfs_tree iso-codes \
    "$(stage "iso-codes-$ISO_CODES_VERSION")/usr/share/xml/iso-codes" \
    /usr/share/xml/iso-codes
install_rootfs_tree iso-codes \
    "$(stage "iso-codes-$ISO_CODES_VERSION")/usr/share/locale/zh_CN" \
    /usr/share/locale/zh_CN

install_rootfs_tree at-spi2 \
    "$(stage "at-spi2-core-$AT_SPI2_CORE_VERSION")/usr/libexec" /usr/libexec
install_rootfs_tree at-spi2 \
    "$(stage "at-spi2-core-$AT_SPI2_CORE_VERSION")/usr/share/dbus-1" \
    /usr/share/dbus-1
install_rootfs_tree gtk3 \
    "$(stage "gtk-$GTK3_VERSION")/usr/share/gtk-3.0" /usr/share/gtk-3.0
install_rootfs_tree gtk3 \
    "$(stage "gtk-$GTK3_VERSION")/usr/share/icons" /usr/share/icons
install_rootfs_tree gtk3 \
    "$(stage "gtk-$GTK3_VERSION")/usr/share/themes" /usr/share/themes
install_new_rootfs_tree qogir-desktop-theme \
    "$(stage "qogir-desktop-theme-$QOGIR_THEME_VERSION")/usr/share/themes/Qogir" \
    /usr/share/themes/Qogir

schema_source="$(stage "gtk-$GTK3_VERSION")/usr/share/glib-2.0/schemas"
while IFS= read -r -d '' schema; do
    install_rootfs_file gtk3 "$schema" \
        "/usr/share/glib-2.0/schemas/$(basename -- "$schema")"
done < <(find "$schema_source" -maxdepth 1 -type f -name '*.xml' -print0)
rm -f "$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas/gschemas.compiled"
remove_rootfs_owner /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas "$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas"
record_rootfs_owner graphical-schemas \
    /usr/share/glib-2.0/schemas/gschemas.compiled

log "Installing runlevel 5 graphical session configuration"
install_rootfs_tree graphical-config "$files_root/etc" /etc
install_rootfs_symlink \
    graphical-config ../../usr/share/X11/xorg.conf.d /etc/X11/xorg.conf.d
sed -E 's/^id:[0-6]:initdefault:$/id:5:initdefault:/' \
    "$EFILINUX_ROOTFS/etc/inittab" > "$assembly/inittab"
replace_rootfs_file \
    graphical-config system-config "$assembly/inittab" /etc/inittab
install_rootfs_symlink \
    graphical-config ../init.d/graphical /etc/rc.d/rc5.d/S80graphical
for runlevel in 0 1 2 3 4 6; do
    install_rootfs_symlink \
        graphical-config ../init.d/graphical "/etc/rc.d/rc${runlevel}.d/K05graphical"
done

mkdir -p \
    "$EFILINUX_ROOTFS/run/user" \
    "$EFILINUX_ROOTFS/var/cache/fontconfig" \
    "$EFILINUX_ROOTFS/var/lib/xkb" \
    "$EFILINUX_ROOTFS/var/log"
touch "$EFILINUX_ROOTFS/var/log/graphical.log"
chmod 0755 \
    "$EFILINUX_ROOTFS/etc/X11/xinit/xinitrc" \
    "$EFILINUX_ROOTFS/etc/rc.d/init.d/graphical"

find "$EFILINUX_ROOTFS/usr/lib/xorg" -type f -name '*.la' -delete
if find "$EFILINUX_ROOTFS" -type f \
    \( -name '*.a' -o -name '*.la' -o -name '*.pc' \) \
    -print -quit | grep -q .; then
    die "development artifact leaked into graphical rootfs"
fi

strip_rootfs_elf
chmod 4755 "$EFILINUX_ROOTFS/usr/libexec/Xorg.wrap"

python3 - "$EFILINUX_ROOTFS" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(sys.argv[1])
missing: dict[str, set[str]] = {}
needed_pattern = re.compile(r"Shared library: \[([^]]+)]")
path_pattern = re.compile(r"Library (?:runpath|rpath): \[(.*?)\]", re.IGNORECASE)

def expand_search_directory(artifact: Path, value: str) -> Path:
    origin = artifact.parent
    value = value.replace("${ORIGIN}", str(origin)).replace("$ORIGIN", str(origin))
    path = Path(value)
    if path.is_absolute():
        try:
            relative = path.relative_to(root)
        except ValueError:
            relative = Path(str(path).lstrip("/"))
        return root / relative
    return origin / path

for artifact in sorted((root / "usr").rglob("*")):
    if artifact.is_symlink() or not artifact.is_file():
        continue
    result = subprocess.run(
        ["readelf", "-d", str(artifact)],
        text=True,
        capture_output=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    if result.returncode != 0:
        continue

    search_directories = [root / "usr/lib", root / "lib"]
    for encoded_path in path_pattern.findall(result.stdout):
        for entry in encoded_path.split(":"):
            if entry:
                search_directories.append(expand_search_directory(artifact, entry))

    unresolved = {
        name
        for name in needed_pattern.findall(result.stdout)
        if not any((directory / name).exists() for directory in search_directories)
    }
    if unresolved:
        missing[str(artifact.relative_to(root))] = unresolved

if missing:
    for artifact, libraries in missing.items():
        print(f"{artifact}: missing {', '.join(sorted(libraries))}", file=sys.stderr)
    raise SystemExit("graphical rootfs has unresolved ELF dependencies")
PY

if find "$EFILINUX_ROOTFS" \
    \( -name 'libwayland-*.so*' -o -name Xwayland -o -path '*/wayland-protocols/*' \) \
    -print -quit | grep -q .; then
    die "Wayland or Xwayland artifacts leaked into the graphical rootfs"
fi

log "Graphical rootfs assembly complete"
