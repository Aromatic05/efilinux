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
((${#desktop_files[@]} >= 12)) || die "recovery module exposes too few desktop applications"
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

privileged_helper="$module_root/opt/recovery/libexec/recovery-privileged-launch"
privileged_policy="$module_root/opt/recovery/share/polkit-1/actions/org.efilinux.recovery.policy"
gtkhash_launcher="$module_root/opt/recovery/bin/gtkhash"
[[ ! -e "$module_root/usr/bin/vkgears" ]] || die "Vulkan demo leaked into recovery"
[[ ! -e "$module_root/usr/bin/vulkaninfo" ]] || die "Vulkan diagnostics leaked into recovery"
[[ -x "$privileged_helper" ]] || die "recovery privileged helper is missing"
[[ -f "$privileged_policy" ]] || die "recovery polkit policy is missing"
grep -Fq '<action id="org.efilinux.recovery.launch-privileged">' "$privileged_policy" ||
    die "recovery polkit action is missing"
grep -Fq '<annotate key="org.freedesktop.policykit.exec.path">/opt/recovery/libexec/recovery-privileged-launch</annotate>' "$privileged_policy" ||
    die "recovery polkit helper path is incorrect"
grep -Fq 'runtime_parent="$XDG_RUNTIME_DIR/efilinux-recovery"' "$gtkhash_launcher" ||
    die "GtkHash does not use the user runtime directory"
if grep -Fq 'runtime_parent=/run/efilinux-recovery' "$gtkhash_launcher"; then
    die "GtkHash still creates a system-level runtime directory"
fi

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
run_command glxinfo -h | grep -Fq 'Usage: glxinfo' ||
    die "recovery GLX diagnostics are not runnable"
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
run_command fio --version >/dev/null
run_command btop --version >/dev/null
run_command mc --version >/dev/null
run_command ncdu --version >/dev/null
run_command nmtui --help >/dev/null

compression_source="$work/compression-source.txt"
compression_output="$work/compression-output.txt"
printf '%s\n' \
    'EFI Linux recovery compression compatibility' \
    'spaces ; semicolons $ dollars and unicode: 恢复' \
    '0123456789abcdef0123456789abcdef' > "$compression_source"

compression_roundtrip() {
    local compressor=$1
    local decompressor=$2
    local archive=$3
    shift 3
    run_command "$compressor" "$@" "$compression_source" > "$archive"
    run_command "$decompressor" -dc "$archive" > "$compression_output"
    cmp "$compression_source" "$compression_output" ||
        die "$compressor compression round trip changed data"
}

compression_roundtrip bzip2 bzip2 "$work/source.bz2" -c
compression_roundtrip pigz pigz "$work/source.gz" -c
compression_roundtrip pbzip2 pbzip2 "$work/source.pbz2" -c
compression_roundtrip lzip lzip "$work/source.lz" -c
compression_roundtrip plzip plzip "$work/source.plz" -c
compression_roundtrip lzop lzop "$work/source.lzo" -c
run_command lz4 -q -c "$compression_source" > "$work/source.lz4"
run_command lz4 -q -d -c "$work/source.lz4" > "$compression_output"
cmp "$compression_source" "$compression_output" ||
    die "lz4 compression round trip changed data"

preview_source="$work/grsync source;literal"
preview_destination="$work/grsync destination dollar$"
mkdir -p "$preview_source" "$preview_destination"
grpreview=$(run_command grsync --preview "$preview_source" "$preview_destination")
python3 - "$grpreview" "$preview_source/" "$preview_destination" <<'PYGRSYNC'
import shlex
import sys

actual = shlex.split(sys.argv[1])
expected = [
    "rsync",
    "--archive",
    "--human-readable",
    "--info=progress2",
    "--partial",
    "--dry-run",
    sys.argv[2],
    sys.argv[3],
]
if actual != expected:
    raise SystemExit(f"Grsync preview argument mismatch: {actual!r}")
PYGRSYNC

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

qt_offscreen_smoke() {
    local name=$1
    local executable log_file home runtime status
    executable=$(find_module_command "$name")
    log_file="$work/$name.log"
    home="$work/$name-home"
    runtime="$work/$name-runtime"
    mkdir -p "$home" "$runtime"
    chmod 0700 "$runtime"
    set +e
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        HOME="$home" \
        XDG_RUNTIME_DIR="$runtime" \
        QT_QPA_PLATFORM=offscreen \
        QT_PLUGIN_PATH="$module_root/opt/recovery/lib/qt6/plugins" \
        timeout 3 \
        "$loader" --library-path "$library_path" "$executable" \
        > "$log_file" 2>&1
    status=$?
    set -e
    [[ $status -eq 124 ]] || {
        cat "$log_file" >&2
        die "$name did not remain operational with the offscreen Qt platform"
    }
}

qt_offscreen_smoke UEFITool
qt_offscreen_smoke qphotorec
qt_offscreen_smoke efibooteditor

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
(( size <= 128 * 1024 * 1024 )) || die "recovery module exceeds 128 MiB: $size"
sha256sum "$artifact"
log "Recovery applications, commands, script interpreters, ELF closure, and size budget passed ($size bytes)"
