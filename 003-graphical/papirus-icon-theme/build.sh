#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=papirus-icon-theme
pkgver=20250501
sysroot=false

depends=(hicolor-icon-theme)
builddepends=()
makedepends=(find python)

prepare() {
    local archive="$downloaddir/papirus-icon-theme-$pkgver.tar.gz"
    download "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 3831a487f813479ad3224fdbfb0c7023f23056899bc78c93737f341aa655558e "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/apps.keep" "$srcdir/apps.keep"
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
    local theme=$1 keep_file=$2

    python3 - "$theme" "$keep_file" <<'PY'
from __future__ import annotations

import configparser
import fnmatch
import os
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
keep_file = Path(sys.argv[2])
allowed_sizes = {"16x16", "18x18", "22x22", "24x24", "32x32", "48x48"}
patterns = [
    line.strip()
    for line in keep_file.read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]

for entry in list(root.iterdir()):
    if entry.name == "index.theme":
        continue
    base_name = entry.name.removesuffix("@2x")
    if base_name not in allowed_sizes:
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()

for size_dir in [path for path in root.iterdir() if path.is_dir() and not path.is_symlink()]:
    apps = size_dir / "apps"
    if not apps.is_dir():
        continue

    selected: set[Path] = set()
    pending: list[Path] = []

    def link_target(path: Path) -> Path:
        return Path(os.path.normpath(path.parent / os.readlink(path)))

    def select(path: Path) -> None:
        if path.parent != apps:
            return
        if not (path.exists() or path.is_symlink()) or path in selected:
            return
        selected.add(path)
        pending.append(path)

    for path in apps.iterdir():
        stem = path.stem
        if any(fnmatch.fnmatchcase(stem, pattern) for pattern in patterns):
            select(path)

    for path in size_dir.rglob("*"):
        if path.parent == apps or not path.is_symlink():
            continue
        select(link_target(path))

    while pending:
        path = pending.pop()
        if not path.is_symlink():
            continue
        select(link_target(path))

    for path in list(apps.iterdir()):
        if path not in selected:
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()

    chromium = apps / "chromium.svg"
    ungoogled = apps / "ungoogled-chromium.svg"
    if chromium.exists() and not ungoogled.exists():
        ungoogled.symlink_to("chromium.svg")

index = root / "index.theme"
parser = configparser.ConfigParser(interpolation=None, strict=False)
parser.optionxform = str
parser.read(index)
parser["Icon Theme"]["Inherits"] = "hicolor"
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
    local theme="$develdir/usr/share/icons/Papirus-Dark"

    mkdir -p "$develdir/usr/share/icons"
    merge_dark_theme \
        "$srcdir/source/Papirus" \
        "$srcdir/source/Papirus-Dark" \
        "$theme"
    prune_theme "$theme" "$srcdir/apps.keep"
}

devel() {
    find "$develdir/usr/share/icons" -type f -name icon-theme.cache -delete
}

package() {
    package_keep /usr/share/icons/Papirus-Dark/
}

recipe_main "$@"
