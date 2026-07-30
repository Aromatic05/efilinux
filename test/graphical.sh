#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"

[[ -f "$EFILINUX_ROOTFS_OWNERS" ]] || die "rootfs ownership manifest is missing"
[[ -f "$EFILINUX_ROOTFS_FAKEROOT_STATE" ]] || die "rootfs fakeroot metadata is missing"

rootfs_owner() {
    local path=$1
    awk -F '\t' -v path="$path" \
        'NR > 1 && $1 == path && $2 != "directory" { print $3; exit }' \
        "$EFILINUX_ROOTFS_OWNERS"
}

rootfs_stat() {
    fakeroot -i "$EFILINUX_ROOTFS_FAKEROOT_STATE" -- \
        stat -c "$1" "$rootfs$2"
}

require_file() {
    local path=$1
    [[ -f "$rootfs$path" ]] || die "graphical file is missing: $path"
}

require_directory() {
    local path=$1
    [[ -d "$rootfs$path" ]] || die "graphical directory is missing: $path"
}

require_program() {
    local name=$1
    local owner=$2
    local path="$rootfs/usr/bin/$name"

    [[ -x "$path" ]] || die "graphical program is missing: $name"
    [[ $(rootfs_owner "/usr/bin/$name") == "$owner" ]] || \
        die "$name is not owned by $owner"
}

require_library() {
    local pattern=$1
    local owner=$2
    local file

    shopt -s nullglob
    for file in "$rootfs/usr/lib"/$pattern; do
        [[ $(rootfs_owner "/usr/lib/$(basename -- "$file")") == "$owner" ]] || \
            die "$(basename -- "$file") is not owned by $owner"
        shopt -u nullglob
        return
    done
    shopt -u nullglob
    die "graphical library family is missing: $pattern"
}

reject_llvm_runtime() {
    if find "$rootfs" \
        \( -name 'libLLVM*.so*' -o -name 'llvm-*' -o -name 'llvm-config' \
           -o -name 'llvm-config-*' -o -name 'libclang*.so*' \
           -o -name 'libLLVMSPIRVLib.*' -o -path '*/usr/share/clc/*' \) \
        -print -quit | grep -q .; then
        die "LLVM runtime leaked into graphical profile"
    fi
}

require_file /etc/X11/xinit/xinitrc
require_file /etc/X11/xorg.conf.d/40-libinput.conf
require_file /home/user/.config/gtk-3.0/settings.ini
require_file /home/user/.config/gtk-4.0/settings.ini
require_file /etc/fonts/fonts.conf
require_file /etc/rc.d/init.d/graphical
require_file /etc/X11/Xwrapper.config
require_directory /usr/share/fonts/truetype/dejavu
require_directory /usr/share/fonts/opentype/noto
require_directory /usr/share/icons/Qogir
require_directory /usr/share/icons/hicolor
require_directory /usr/share/mime
require_directory /usr/share/X11/xkb
require_directory /usr/lib/xorg/modules/drivers
require_directory /usr/lib/xorg/modules/input
require_directory /usr/lib/dri

require_program Xorg xorg-server
[[ -x "$rootfs/usr/libexec/Xorg" ]] || die "real Xorg server is missing"
[[ -x "$rootfs/usr/libexec/Xorg.wrap" ]] || die "Xorg setuid wrapper is missing"
[[ $(rootfs_stat '%a' /usr/libexec/Xorg.wrap) == 4755 ]] || \
    die "Xorg wrapper is not setuid root"
grep -Fxq 'allowed_users=anybody' "$rootfs/etc/X11/Xwrapper.config" ||     die "Xorg wrapper does not permit the live user"
grep -Fxq 'needs_root_rights=yes' "$rootfs/etc/X11/Xwrapper.config" ||     die "Xorg wrapper does not retain required device privileges"
require_program xinit xorg
require_program startx xorg
require_program xkbcomp xorg
require_program xwininfo xorg
require_program xauth xorg
require_program iceauth xorg
require_program mcookie util-linux
require_program gtk3-demo gtk3
require_program gtk3-widget-factory gtk3
require_program gdk-pixbuf-query-loaders gdk-pixbuf
require_program gdk-pixbuf-csource gdk-pixbuf
require_program fc-cache fontconfig
require_program fc-match fontconfig
require_program gtk-update-icon-cache gtk3
require_program update-mime-database shared-mime-info
require_program update-desktop-database desktop-file-utils

require_library 'libdrm.so.2*' libdrm
require_library 'libgbm.so.1*' mesa
require_library 'libEGL.so.1*' mesa
require_library 'libGL.so.1*' mesa
require_library 'libgtk-3.so.0*' gtk3
require_library 'libgdk-3.so.0*' gtk3
require_library 'libcairo.so.2*' cairo
require_library 'libpango-1.0.so.0*' pango
require_library 'librsvg-2.so.2*' librsvg
require_library 'libfontconfig.so.1*' fontconfig
require_library 'libfreetype.so.6*' freetype
require_library 'libICE.so.6*' xorg
require_library 'libSM.so.6*' xorg
require_library 'libXt.so.6*' xorg
require_library 'libXmu.so.6*' xorg

for driver in \
    iris_dri.so crocus_dri.so radeonsi_dri.so nouveau_dri.so \
    virtio_gpu_dri.so swrast_dri.so; do
    require_file "/usr/lib/dri/$driver"
done

reject_llvm_runtime

for module in \
    /usr/lib/xorg/modules/drivers/modesetting_drv.so \
    /usr/lib/xorg/modules/drivers/fbdev_drv.so \
    /usr/lib/xorg/modules/input/libinput_drv.so; do
    require_file "$module"
done

for font in DejaVuSans.ttf DejaVuSansMono.ttf; do
    require_file "/usr/share/fonts/truetype/dejavu/$font"
done
require_file /usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf
require_file /usr/share/icons/Qogir/index.theme
require_file /usr/share/icons/Qogir/icon-theme.cache
require_file /usr/share/icons/hicolor/index.theme
require_file /usr/share/icons/hicolor/icon-theme.cache
require_file /usr/share/mime/packages/freedesktop.org.xml
require_file /usr/share/mime/mime.cache
require_file /usr/share/applications/mimeinfo.cache
[[ $(rootfs_owner /usr/share/icons/Qogir/icon-theme.cache) == @composer ]] || \
    die "Qogir icon cache is not owned by the composer"
[[ $(rootfs_owner /usr/share/icons/hicolor/icon-theme.cache) == @composer ]] || \
    die "hicolor icon cache is not owned by the composer"
[[ $(rootfs_owner /usr/share/mime/mime.cache) == @composer ]] || \
    die "MIME cache is not owned by the composer"
[[ $(rootfs_owner /usr/share/applications/mimeinfo.cache) == @composer ]] || \
    die "desktop MIME cache is not owned by the composer"
require_file /usr/share/xml/iso-codes/iso_639-2.xml
require_file /usr/share/xml/iso-codes/iso_3166-1.xml
[[ -L "$rootfs/usr/share/xml/iso-codes/iso_639.xml" ]] || \
    die "legacy ISO 639 data link is missing"
[[ -L "$rootfs/usr/share/xml/iso-codes/iso_3166.xml" ]] || \
    die "legacy ISO 3166 data link is missing"
require_file /usr/share/locale/zh_CN/LC_MESSAGES/iso_639-2.mo
require_file /usr/share/locale/zh_CN/LC_MESSAGES/iso_3166-1.mo
if find "$rootfs/usr/share/xml/iso-codes" -maxdepth 1 -type f \
    ! -name 'iso_639-2.xml' ! -name 'iso_3166-1.xml' -print -quit | grep -q .; then
    die "unneeded ISO code domains leaked into the graphical rootfs"
fi
[[ -e "$rootfs/usr/share/icons/Qogir/cursors/left_ptr" ]] || \
    die "Qogir cursor theme is missing left_ptr"
if find -L "$rootfs/usr/share/icons/Qogir" -type l -print -quit | grep -q .; then
    die "Qogir icon theme contains broken symbolic links"
fi

svg_loader=$(find "$rootfs/usr/lib/gdk-pixbuf-2.0" \
    -type f -name libpixbufloader-svg.so -print -quit)
[[ -n "$svg_loader" ]] || die "GdkPixbuf SVG loader is missing"
[[ $(rootfs_owner "${svg_loader#"$rootfs"}") == librsvg ]] || \
    die "GdkPixbuf SVG loader is not owned by librsvg"
loader_cache="$(dirname -- "$(dirname -- "$svg_loader")")/loaders.cache"
[[ -s "$loader_cache" ]] || die "GdkPixbuf loader cache is missing"
grep -Fq '"svg"' "$loader_cache" || \
    die "GdkPixbuf loader cache does not register SVG"
if grep -Fq "$rootfs" "$loader_cache"; then
    die "GdkPixbuf loader cache contains build-host paths"
fi

mapfile -t qogir_variants < <(
    find "$rootfs/usr/share/icons" -maxdepth 1 -mindepth 1 \
        -type d -name 'Qogir*' -printf '%f\n' | sort
)
[[ ${#qogir_variants[@]} -eq 1 && ${qogir_variants[0]} == Qogir ]] || \
    die "graphical rootfs contains more than one Qogir color variant"

[[ -L "$rootfs/etc/rc.d/rc5.d/S80graphical" ]] || \
    die "runlevel 5 does not start the graphical session"
grep -Eq '^id:5:initdefault:$' "$rootfs/etc/inittab" || \
    die "graphical image does not default to runlevel 5"
grep -Fq 'GDK_BACKEND=x11' "$rootfs/etc/rc.d/init.d/graphical" || \
    die "graphical service does not force the GTK X11 backend"
grep -Fq '/usr/bin/su -s /usr/bin/sh user -c'     "$rootfs/etc/rc.d/init.d/graphical" ||     die "graphical service does not launch the normal user"
grep -Fq 'HOME=/home/user' "$rootfs/etc/rc.d/init.d/graphical" ||     die "graphical service does not use the normal user home"
if grep -Eq '/run/user/0|HOME=/root|USER=root' "$rootfs/etc/rc.d/init.d/graphical"; then
    die "graphical service still starts a root desktop session"
fi

if find "$rootfs" \
    \( -name 'libwayland-*.so*' -o -name 'Xwayland' -o -path '*/wayland-protocols/*' \) \
    -print -quit | grep -q .; then
    die "Wayland or Xwayland artifacts leaked into 003-graphical"
fi

python3 - "$rootfs" <<'PY'
from pathlib import Path
import os
import subprocess
import sys

root = Path(sys.argv[1])
for artifact in sorted((root / "usr").rglob("*")):
    if artifact.is_symlink() or not artifact.is_file():
        continue
    result = subprocess.run(
        ["readelf", "-d", str(artifact)],
        text=True,
        capture_output=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    if result.returncode == 0 and "libwayland" in result.stdout:
        print(f"Wayland dependency leaked into {artifact.relative_to(root)}", file=sys.stderr)
        raise SystemExit(1)
PY

if ! "$loader" --library-path "$library_path" \
    "$rootfs/usr/libexec/Xorg" -version 2>&1 | grep -q 'X.Org X Server'; then
    die "real Xorg server does not execute against the target library closure"
fi
"$loader" --library-path "$library_path" "$rootfs/usr/bin/gtk3-demo" --help-all >/dev/null
"$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/gdk-pixbuf-query-loaders" "$svg_loader" | \
    grep -Fq '"svg"'
host_loader_cache="$EFILINUX_TEST/gdk-pixbuf-loaders.host.cache"
decoded_icon="$EFILINUX_TEST/qogir-terminal-icon.c"
"$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/gdk-pixbuf-query-loaders" "$svg_loader" \
    > "$host_loader_cache"
GDK_PIXBUF_MODULE_FILE="$host_loader_cache" \
    "$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/gdk-pixbuf-csource" \
    --raw --name=qogir_terminal_icon \
    "$rootfs/usr/share/icons/Qogir/scalable/apps/org.xfce.terminal.svg" \
    > "$decoded_icon"
grep -Fq 'qogir_terminal_icon' "$decoded_icon" || \
    die "GdkPixbuf could not decode a real Qogir SVG icon"
mime_test_dir="$EFILINUX_TEST/mime"
reset_directory "$mime_test_dir"
printf '\211PNG\r\n\032\n' > "$mime_test_dir/image.png"
printf '%%PDF-1.7\n' > "$mime_test_dir/document.pdf"
for mime_case in 'image.png:image/png' 'document.pdf:application/pdf'; do
    mime_file=${mime_case%%:*}
    expected_type=${mime_case#*:}
    actual_type=$(
        XDG_DATA_DIRS="$rootfs/usr/share" \
        GIO_MODULE_DIR="$rootfs/usr/lib/gio/modules" \
        "$loader" --library-path "$library_path" \
            "$rootfs/usr/bin/gio" info -a standard::content-type \
            "$mime_test_dir/$mime_file" | \
            sed -n 's/^[[:space:]]*standard::content-type:[[:space:]]*//p'
    )
    [[ $actual_type == "$expected_type" ]] || \
        die "$mime_file resolved as $actual_type, expected $expected_type"
done

FONTCONFIG_SYSROOT="$rootfs" \
    "$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/fc-match" -f '%{family}\n' ':lang=zh-cn' | \
    grep -Fq 'Noto Sans CJK SC'

require_library 'libXss.so.1*' xorg
require_library 'libxklavier.so.16*' libxklavier
require_library 'libdbus-glib-1.so.2*' dbus-glib
require_library 'libvte-2.91.so.0*' vte

log "003-graphical Xorg, Mesa, GTK, bilingual fonts, Qogir, and no-Wayland contract passed"
