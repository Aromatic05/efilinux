#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=papirus-maia-icon-theme
pkgver=20201007
sysroot=false

depends=(papirus-icon-theme)
builddepends=()
makedepends=(find python)

prepare() {
    local archive="$downloaddir/papirus-maia-icon-theme-$pkgver.tar.gz"
    download "https://gitlab.manjaro.org/artwork/icon-themes/papirus-maia-icon-theme/-/archive/4902405a228410ace965679c324fef88bff3a723/papirus-maia-icon-theme-4902405a228410ace965679c324fef88bff3a723.tar.gz" "$archive"
    checksum sha256 952880851bc738ccb971b5ed05871ebb24d1d516b122c2ced14b058c28434728 "$archive"
    extract "$archive" "$srcdir/source"
}

merge_dark_theme() {
    local base=$1 overlay=$2 destination=$3 path relative

    cp -a "$base" "$destination"
    while IFS= read -r -d '' path; do
        relative=${path#"$overlay"/}
        if [[ -d "$path" ]]; then
            mkdir -p "$destination/$relative"
        else
            mkdir -p "$(dirname -- "$destination/$relative")"
            cp -a "$path" "$destination/$relative"
        fi
    done < <(find "$overlay" -mindepth 1 ! -type l -print0)
}

prune_theme() {
    local theme=$1

    python3 - "$theme" <<'PY'
from __future__ import annotations

import configparser
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
allowed_sizes = {"16x16", "22x22", "24x24", "32x32", "48x48"}

for entry in list(root.iterdir()):
    if entry.name == "index.theme":
        continue
    base_name = entry.name.removesuffix("@2x")
    if base_name not in allowed_sizes:
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()

index = root / "index.theme"
parser = configparser.ConfigParser(interpolation=None, strict=False)
parser.optionxform = str
parser.read(index)
parser["Icon Theme"]["Inherits"] = "Papirus-Dark,hicolor"
parser["Icon Theme"]["DesktopSizes"] = "16,22,24,32,48"
parser["Icon Theme"]["ToolbarSizes"] = "16,22,24,32,48"
parser["Icon Theme"]["MainToolbarSizes"] = "16,22,24,32,48"
parser["Icon Theme"]["SmallSizes"] = "16,22,24,32,48"
parser["Icon Theme"]["PanelSizes"] = "16,22,24,32,48"
parser["Icon Theme"]["DialogSizes"] = "16,22,24,32,48"

existing = []
for section in list(parser.sections()):
    if section == "Icon Theme":
        continue
    if not (root / section).is_dir():
        parser.remove_section(section)
    else:
        existing.append(section)

normal = [item for item in existing if "@2x/" not in item]
scaled = [item for item in existing if "@2x/" in item]
parser["Icon Theme"]["Directories"] = ",".join(normal)
if scaled:
    parser["Icon Theme"]["ScaledDirectories"] = ",".join(scaled)
elif parser.has_option("Icon Theme", "ScaledDirectories"):
    parser.remove_option("Icon Theme", "ScaledDirectories")

with index.open("w") as stream:
    parser.write(stream, space_around_delimiters=False)
PY
}

build() {
    local theme="$develdir/usr/share/icons/Papirus-Dark-Maia"

    mkdir -p "$develdir/usr/share/icons"
    merge_dark_theme \
        "$srcdir/source/Papirus-Maia" \
        "$srcdir/source/Papirus-Dark-Maia" \
        "$theme"
    prune_theme "$theme"
}

devel() {
    find "$develdir/usr/share/icons" -type f -name icon-theme.cache -delete
}

package() {
    package_keep /usr/share/icons/Papirus-Dark-Maia/
}

recipe_main "$@"
