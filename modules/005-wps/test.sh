#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command bash desktop-file-validate python3 readelf sha256sum timeout unsquashfs

artifact="$ROOT/modules/output/005-wps.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
base_root="$EFILINUX_ROOTFS"
loader="$base_root/usr/lib/ld-linux-x86-64.so.2"

[[ -f "$artifact" ]] || die "WPS module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

mapfile -d '' desktop_files < <(find "$module_root" -type f -name '*.desktop' -print0)
((${#desktop_files[@]} >= 3)) || die "WPS module does not expose Writer, Spreadsheets, and Presentation"
desktop-file-validate "${desktop_files[@]}"

python3 - "$module_root" "$base_root" "${desktop_files[@]}" <<'PY'
from pathlib import Path
import configparser
import os
import shlex
import sys

module_root = Path(sys.argv[1])
base_root = Path(sys.argv[2])
for desktop_name in sys.argv[3:]:
    desktop = Path(desktop_name)
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(desktop)
    command = shlex.split(parser["Desktop Entry"].get("Exec", ""))[0]
    candidates = []
    if command.startswith("/"):
        candidates.extend((module_root / command.lstrip("/"), base_root / command.lstrip("/")))
    else:
        candidates.extend((module_root / "usr/bin" / command, base_root / "usr/bin" / command))
    if not any(path.exists() and os.access(path, os.X_OK) for path in candidates):
        raise SystemExit(f"{desktop}: unavailable command: {command}")
print(f"WPS desktop integration: {len(sys.argv) - 3} launchers resolved")
PY

for launcher in "$module_root/usr/bin/wps" "$module_root/usr/bin/et" "$module_root/usr/bin/wpp"; do
    [[ -x "$launcher" ]] || die "WPS launcher is unavailable: ${launcher##*/}"
    bash -n "$launcher"
done

mapfile -d '' library_directories < <(
    find "$module_root" -type f -name '*.so*' -printf '%h\0' | sort -zu
)
library_path="$base_root/usr/lib"
for directory in "${library_directories[@]}"; do
    library_path="$directory:$library_path"
done

python3 - "$module_root" "$base_root" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

module_root = Path(sys.argv[1])
base_root = Path(sys.argv[2])
library_directories = {base_root / "usr/lib"}
elf_files = []
for path in module_root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    with path.open("rb") as stream:
        if stream.read(4) != b"\x7fELF":
            continue
    elf_files.append(path)
    library_directories.add(path.parent)
missing = []
for path in elf_files:
    dynamic = subprocess.run(
        ["readelf", "-d", str(path)], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    ).stdout
    for soname in re.findall(r"Shared library: \[(.*?)\]", dynamic):
        if not any((directory / soname).exists() for directory in library_directories):
            missing.append((path, soname))
if missing:
    for path, soname in missing:
        print(f"{path}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)
print(f"WPS module ELF closure: {len(elf_files)} files")
PY

for name in wps et wpp; do
    binary=$(find "$module_root/opt" -type f -name "$name" -perm -0100 -print -quit)
    [[ -n "$binary" ]] || die "WPS application is unavailable: $name"
    "$loader" --library-path "$library_path" --list "$binary" >/dev/null
    set +e
    timeout 10 env -u LD_PRELOAD \
        LD_LIBRARY_PATH="$library_path" HOME="$work/home-$name" DISPLAY= \
        "$binary" --help >/dev/null 2>&1
    status=$?
    set -e
    (( status != 124 && status != 126 && status != 127 )) ||
        die "WPS $name did not reach application startup: $status"
done

size=$(stat -c %s "$artifact")
(( size <= 128 * 1024 * 1024 )) || die "WPS module exceeds 128 MiB: $size"
sha256sum "$artifact"
log "WPS desktop integration, launchers, ELF closure, application startup, and size budget passed ($size bytes)"
