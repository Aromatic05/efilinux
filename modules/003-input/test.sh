#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command desktop-file-validate python3 readelf sha256sum unsquashfs

artifact="$ROOT/modules/output/003-input.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
loader="$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2"

[[ -f "$artifact" ]] || die "input module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

mapfile -d '' desktop_files < <(find "$module_root/usr/share/applications" -maxdepth 1 -type f -name '*.desktop' -print0)
((${#desktop_files[@]} > 0)) || die "input module exposes no desktop integration"
desktop-file-validate "${desktop_files[@]}"

python3 - "$module_root" "$EFILINUX_ROOTFS" "${desktop_files[@]}" <<'PY'
from pathlib import Path
import configparser
import shlex
import sys

module_root = Path(sys.argv[1])
base_root = Path(sys.argv[2])
desktop_files = [Path(path) for path in sys.argv[3:]]
resolved = 0

for desktop in desktop_files:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(desktop)
    entry = parser["Desktop Entry"]
    command = shlex.split(entry.get("Exec", ""))[0]
    if not command.startswith("/"):
        raise SystemExit(f"{desktop}: Exec must use an absolute command")
    if not ((module_root / command.lstrip("/")).exists() or
            (base_root / command.lstrip("/")).exists()):
        raise SystemExit(f"{desktop}: Exec command is unavailable: {command}")
    icon = entry.get("Icon", "")
    if not icon.startswith("/"):
        raise SystemExit(f"{desktop}: module-owned application icon is not directly resolvable")
    if not (module_root / icon.lstrip("/")).exists():
        raise SystemExit(f"{desktop}: application icon is unavailable: {icon}")
    resolved += 1

print(f"input desktop integration: {resolved} launchers resolved")
PY

configtool="$module_root/opt/fcitx5/bin/fcitx5-configtool"
[[ -x "$configtool" ]] || die "input module contains no configuration tool"
[[ $(head -c 4 "$configtool") == $'\x7fELF' ]] || \
    die "Fcitx configuration entry does not launch a graphical configuration program"

for addon in classicui dbus dbusfrontend notificationitem xcb xim; do
    [[ -f "$module_root/opt/fcitx5/share/fcitx5/addon/$addon.conf" ]] || \
        die "input module is missing the $addon addon configuration"
    [[ -f "$module_root/opt/fcitx5/lib/fcitx5/lib$addon.so" ]] || \
        die "input module is missing the $addon addon runtime"
done

profile="$module_root/opt/fcitx5/share/efilinux/profile"
[[ -f "$profile" ]] || die "input module contains no default input method profile"
awk -F= '
    $1 == "DefaultIM" && $2 == "pinyin" { default_ok=1 }
    $1 == "Name" && $2 == "keyboard-us" { keyboard_ok=1 }
    $1 == "Name" && $2 == "pinyin" { pinyin_ok=1 }
    END { exit !(default_ok && keyboard_ok && pinyin_ok) }
' "$profile" || die "default input method profile does not enable Pinyin with keyboard fallback"

fcitx_binary=$(find "$module_root" -type f -name fcitx5 -print -quit)
[[ -n "$fcitx_binary" ]] || die "input module contains no fcitx5 runtime"
library_path=$(find "$module_root" -type f -name 'libFcitx5Core.so.*' -printf '%h\n' -quit)
[[ -n "$library_path" ]] || die "input module contains no Fcitx runtime library directory"
"$loader" --library-path "$library_path:$EFILINUX_ROOTFS/usr/lib" \
    "$fcitx_binary" --version >/dev/null

python3 - "$module_root" "$EFILINUX_ROOTFS" <<'PY'
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
    result = subprocess.run(
        ["readelf", "-d", str(path)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    for soname in re.findall(r"Shared library: \[(.*?)\]", result.stdout):
        if not any((directory / soname).exists() for directory in library_directories):
            missing.append((path, soname))

if missing:
    for path, soname in missing:
        print(f"{path}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)

print(f"input module ELF closure: {len(elf_files)} files")
PY

size=$(stat -c %s "$artifact")
(( size <= 48 * 1024 * 1024 )) || die "input module exceeds 48 MiB: $size"
sha256sum "$artifact"
log "Input module tray, configuration, default profile, desktop integration, ELF closure, and size budget passed ($size bytes)"
