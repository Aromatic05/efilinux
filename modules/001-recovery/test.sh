#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command desktop-file-validate python3 readelf sha256sum unsquashfs

artifact="$ROOT/modules/output/001-recovery.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
loader="$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2"

[[ -f "$artifact" ]] || die "recovery module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

mapfile -d '' desktop_files < <(find "$module_root" -type f -name '*.desktop' -print0)
((${#desktop_files[@]} >= 3)) || die "recovery module exposes too few desktop applications"
desktop-file-validate "${desktop_files[@]}"

python3 - "$module_root" "$EFILINUX_ROOTFS" "${desktop_files[@]}" <<'PY'
from pathlib import Path
import configparser
import os
import shlex
import sys

module_root = Path(sys.argv[1])
base_root = Path(sys.argv[2])
desktop_files = [Path(path) for path in sys.argv[3:]]


def mapped(path: str) -> Path:
    return module_root / path.lstrip("/")


def resolve(path: Path) -> Path:
    seen: set[Path] = set()
    while path.is_symlink():
        if path in seen:
            raise SystemExit(f"symlink loop: {path}")
        seen.add(path)
        target = os.readlink(path)
        path = mapped(target) if target.startswith("/") else path.parent / target
    return path

resolved = 0
for desktop in desktop_files:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(desktop)
    command = shlex.split(parser["Desktop Entry"].get("Exec", ""))[0]
    if not command.startswith("/"):
        raise SystemExit(f"{desktop}: Exec must use an absolute command")
    candidate = resolve(mapped(command))
    if not candidate.exists():
        candidate = base_root / command.lstrip("/")
    if not candidate.exists() or not os.access(candidate, os.X_OK):
        raise SystemExit(f"{desktop}: unavailable command: {command}")
    resolved += 1

print(f"recovery desktop integration: {resolved} launchers resolved")
PY

mapfile -d '' library_directories < <(
    find "$module_root" -type f -name '*.so*' -printf '%h\0' | sort -zu
)
library_path="$EFILINUX_ROOTFS/usr/lib"
for directory in "${library_directories[@]}"; do
    library_path="$directory:$library_path"
done

run_command() {
    local name=$1
    shift
    local command

    command=$(find "$module_root" -type f -name "$name" -perm -0100 -print -quit)
    [[ -n "$command" ]] || die "recovery command is unavailable: $name"
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" "$command" "$@" >/dev/null
}

run_command testdisk /version
run_command photorec /version
run_command fsarchiver --version
run_command qemu-img --version
run_command wimlib-imagex --version
run_command jq --version

python3 - "$module_root" "$EFILINUX_ROOTFS" <<'PY'
from pathlib import Path
import os
import re
import shlex
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
        prefix = stream.read(256)
    if prefix.startswith(b"\x7fELF"):
        elf_files.append(path)
        library_directories.add(path.parent)
        continue
    if not prefix.startswith(b"#!") or not os.access(path, os.X_OK):
        continue
    shebang = prefix.splitlines()[0][2:].decode("utf-8", "replace").strip()
    interpreter = shlex.split(shebang)[0]
    if not interpreter.startswith("/"):
        raise SystemExit(f"{path}: relative shebang interpreter: {interpreter}")
    if not ((module_root / interpreter.lstrip("/")).exists() or
            (base_root / interpreter.lstrip("/")).exists()):
        raise SystemExit(f"{path}: missing shebang interpreter: {interpreter}")

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

print(f"recovery module ELF closure: {len(elf_files)} files")
PY

size=$(stat -c %s "$artifact")
(( size <= 64 * 1024 * 1024 )) || die "recovery module exceeds 64 MiB: $size"
sha256sum "$artifact"
log "Recovery applications, commands, script interpreters, ELF closure, and size budget passed ($size bytes)"
