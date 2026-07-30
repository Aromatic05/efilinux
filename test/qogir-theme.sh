#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

rootfs="$EFILINUX_ROOTFS"
theme="$rootfs/usr/share/icons/Qogir"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"

[[ -d "$theme" ]] || die "Qogir theme is missing"
[[ -s "$theme/index.theme" ]] || die "Qogir index is missing"
[[ -s "$theme/icon-theme.cache" ]] || die "Qogir icon cache is missing"
[[ $(awk -F= '$1 == "Inherits" { print $2; exit }' "$theme/index.theme") == hicolor ]] || \
    die "Qogir does not use hicolor as its module icon fallback"

if find -L "$theme" -type l -print -quit | grep -q .; then
    die "Qogir contains a broken symbolic link"
fi

apparent_bytes=$(du -sb "$theme" | awk '{print $1}')
entry_count=$(find "$theme" -mindepth 1 | wc -l)
((apparent_bytes < 16 * 1024 * 1024)) || \
    die "Qogir apparent size regressed: $apparent_bytes bytes"
((entry_count < 9000)) || die "Qogir entry count regressed: $entry_count"

python3 - "$rootfs" <<'PY'
from __future__ import annotations

import configparser
import sys
from pathlib import Path

root = Path(sys.argv[1])
theme = root / "usr/share/icons/Qogir"
hicolor = root / "usr/share/icons/hicolor"
pixmaps = root / "usr/share/pixmaps"

parser = configparser.ConfigParser(interpolation=None)
parser.optionxform = str
parser.read(theme / "index.theme", encoding="utf-8")
directories = parser["Icon Theme"]["Directories"].split(",")
for directory in directories:
    path = theme / directory
    if not path.is_dir() or not any(path.iterdir()):
        raise SystemExit(f"declared Qogir directory is empty: {directory}")

extensions = (".svg", ".png", ".xpm")

def contains_icon(base: Path, name: str) -> bool:
    if not base.is_dir():
        return False
    for extension in extensions:
        if any(base.rglob(name + extension)):
            return True
    return False

missing: list[str] = []
for desktop in sorted((root / "usr/share/applications").glob("*.desktop")):
    for raw_line in desktop.read_text(errors="replace").splitlines():
        if not raw_line.startswith("Icon="):
            continue
        icon = raw_line.removeprefix("Icon=").strip()
        if not icon or icon.startswith("/"):
            break
        if not (
            contains_icon(theme, icon)
            or contains_icon(hicolor, icon)
            or any((pixmaps / f"{icon}{extension}").exists() for extension in extensions)
        ):
            missing.append(f"{desktop.name}:{icon}")
        break
if missing:
    raise SystemExit("desktop icons do not resolve: " + ", ".join(missing))
PY

for icon in \
    scalable/apps/org.xfce.terminal.svg \
    scalable/apps/org.xfce.thunar.svg \
    scalable/devices/drive-harddisk.svg \
    scalable/mimetypes/application-pdf.svg \
    128/places/folder.svg \
    symbolic/actions/edit-copy-symbolic.svg \
    symbolic/status/network-wireless-signal-excellent-symbolic.svg \
    cursors/left_ptr; do
    [[ -e "$theme/$icon" ]] || die "required Qogir runtime icon is missing: $icon"
done

svg_loader=$(find "$rootfs/usr/lib/gdk-pixbuf-2.0" \
    -type f -name libpixbufloader-svg.so -print -quit)
[[ -n "$svg_loader" ]] || die "GdkPixbuf SVG loader is missing"
host_loader_cache="$EFILINUX_TEST/qogir-gdk-pixbuf-loaders.cache"
"$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/gdk-pixbuf-query-loaders" "$svg_loader" > "$host_loader_cache"
for icon in \
    scalable/apps/org.xfce.terminal.svg \
    scalable/devices/drive-harddisk.svg \
    scalable/mimetypes/application-pdf.svg \
    symbolic/status/network-wireless-signal-excellent-symbolic.svg; do
    output="$EFILINUX_TEST/qogir-$(basename -- "$icon").c"
    GDK_PIXBUF_MODULE_FILE="$host_loader_cache" \
        "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/gdk-pixbuf-csource" --raw --name=qogir_test_icon \
        "$theme/$icon" > "$output"
    grep -Fq qogir_test_icon "$output" || die "failed to decode Qogir icon: $icon"
done

log "Qogir runtime closure, desktop icon resolution, SVG decoding, and size limits passed"
