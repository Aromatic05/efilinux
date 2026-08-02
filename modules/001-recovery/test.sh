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

find_module_command() {
    local name=$1
    local command

    command=$(find "$module_root" -type f -name "$name" -perm -0100 -print -quit)
    [[ -n "$command" ]] || die "recovery command is unavailable: $name"
    printf '%s\n' "$command"
}

run_command() {
    local name=$1
    shift
    local command

    command=$(find_module_command "$name")
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" "$command" "$@"
}

run_command testdisk /version >/dev/null
run_command photorec /version >/dev/null
run_command fsarchiver --version >/dev/null
run_command qemu-img --version >/dev/null
run_command wimlib-imagex --version >/dev/null
run_command jq --version >/dev/null
run_command grub-install --version >/dev/null
run_command ms-sys --version >/dev/null
run_command flashrom --version >/dev/null
run_command xorriso -version >/dev/null
run_command cdrskin --version >/dev/null
run_command UEFIExtract --version >/dev/null
run_command UEFIFind --version >/dev/null

iso_source="$work/iso-source"
iso_image="$work/recovery-tools.iso"
iso_extracted="$work/iso-extracted.txt"
mkdir -p "$iso_source"
printf 'efilinux optical media test\n' > "$iso_source/marker.txt"
run_command xorriso \
    -as mkisofs \
    -quiet \
    -o "$iso_image" \
    "$iso_source" >/dev/null 2>&1
run_command xorriso \
    -osirrox on \
    -indev "$iso_image" \
    -extract /marker.txt "$iso_extracted" >/dev/null 2>&1
cmp "$iso_source/marker.txt" "$iso_extracted"

grub_library="$module_root/opt/recovery/lib/grub"
run_command grub-mkimage \
    -O x86_64-efi \
    -d "$grub_library/x86_64-efi" \
    -p /boot/grub \
    -o "$work/grubx64.efi" \
    part_gpt fat normal
run_command grub-mkimage \
    -O i386-pc \
    -d "$grub_library/i386-pc" \
    -p /boot/grub \
    -o "$work/core.img" \
    biosdisk part_msdos ext2 normal
[[ -s "$work/grubx64.efi" && -s "$work/core.img" ]] || \
    die "GRUB failed to generate EFI and BIOS images"
[[ $(od -An -tx1 -N2 "$work/grubx64.efi" | tr -d ' \n') == 4d5a ]] || \
    die "GRUB x86_64-efi image is not a PE executable"

truncate -s 1M "$work/windows-mbr.img"
before_mbr=$(sha256sum "$work/windows-mbr.img" | awk '{ print $1 }')
run_command ms-sys --mbr7 --force "$work/windows-mbr.img" >/dev/null
after_mbr=$(sha256sum "$work/windows-mbr.img" | awk '{ print $1 }')
[[ $before_mbr != "$after_mbr" ]] || die "ms-sys did not write the test MBR"
[[ $(od -An -tx1 -j510 -N2 "$work/windows-mbr.img" | tr -d ' \n') == 55aa ]] || \
    die "ms-sys did not write an MBR signature"

run_command flashrom \
    -p dummy:emulate=VARIABLE_SIZE,size=8388608 \
    -r "$work/dummy-flash.bin" >/dev/null 2>&1
[[ $(stat -c %s "$work/dummy-flash.bin") -eq 8388608 ]] || \
    die "flashrom dummy programmer did not read the emulated 8 MiB chip"

run_command mkudffs \
    --new-file \
    --blocksize=2048 \
    --media-type=hd \
    --label=EFILINUX_TEST \
    "$work/recovery-tools.udf" 8192 >/dev/null
run_command udfinfo "$work/recovery-tools.udf" > "$work/udfinfo.txt"
grep -Fq 'label=EFILINUX_TEST' "$work/udfinfo.txt" || \
    grep -Fq 'vid=EFILINUX_TEST' "$work/udfinfo.txt" || \
    die "udfinfo did not report the generated UDF label"

uefitool=$(find_module_command UEFITool)
mkdir -p "$work/uefitool-home" "$work/uefitool-runtime"
chmod 0700 "$work/uefitool-runtime"
set +e
env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    HOME="$work/uefitool-home" \
    XDG_RUNTIME_DIR="$work/uefitool-runtime" \
    QT_QPA_PLATFORM=offscreen \
    QT_PLUGIN_PATH="$module_root/opt/recovery/lib/qt6/plugins" \
    timeout 3 \
    "$loader" --library-path "$library_path" "$uefitool" \
    > "$work/uefitool.log" 2>&1
uefitool_status=$?
set -e
[[ $uefitool_status -eq 124 ]] || {
    cat "$work/uefitool.log" >&2
    die "UEFITool did not remain operational with the offscreen Qt platform"
}

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
