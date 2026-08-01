#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command desktop-file-validate python3 readelf sha256sum timeout unsquashfs

artifact="$ROOT/modules/output/004-browser.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
base_root="$EFILINUX_ROOTFS"
loader="$base_root/usr/lib/ld-linux-x86-64.so.2"

[[ -f "$artifact" ]] || die "browser module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

mapfile -d '' desktop_files < <(find "$module_root" -type f -name '*.desktop' -print0)
((${#desktop_files[@]} > 0)) || die "browser module exposes no desktop application"
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
print(f"browser desktop integration: {len(sys.argv) - 3} launcher resolved")
PY

browser=$(find "$module_root/opt" -type f -name chrome -perm -0100 -print -quit)
[[ -n "$browser" ]] || die "browser executable is unavailable"
launcher=$(find "$module_root/usr/bin" -type f -name 'ungoogled-chromium' -print -quit)
[[ -n "$launcher" ]] || die "browser launcher is unavailable"
bash -n "$launcher"

mapfile -d '' library_directories < <(
    find "$module_root" -type f -name '*.so*' -printf '%h\0' | sort -zu
)
library_path="$base_root/usr/lib"
for directory in "${library_directories[@]}"; do
    library_path="$directory:$library_path"
done

env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    "$loader" --library-path "$library_path" "$browser" --version >/dev/null

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
print(f"browser module ELF closure: {len(elf_files)} files")
PY

mkdir -p "$work/home" "$work/config" "$work/cache"
timeout 20 env -u LD_PRELOAD \
    LD_LIBRARY_PATH="$library_path" \
    HOME="$work/home" \
    XDG_CONFIG_HOME="$work/config" \
    XDG_CACHE_HOME="$work/cache" \
    "$browser" \
    --no-sandbox \
    --headless=new \
    --disable-background-networking \
    --user-data-dir="$work/profile" \
    --dump-dom 'data:text/html,<html><body>efilinux-browser-smoke</body></html>' \
    >"$work/headless.out" 2>"$work/headless.err"
grep -Fq 'efilinux-browser-smoke' "$work/headless.out" ||
    die "browser headless rendering did not return the requested document"

size=$(stat -c %s "$artifact")
(( size <= 128 * 1024 * 1024 )) || die "browser module exceeds 128 MiB: $size"
sha256sum "$artifact"
log "Browser desktop integration, runtime, ELF closure, headless rendering, and size budget passed ($size bytes)"
