#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command python3 readelf sha256sum unsquashfs

artifact="$ROOT/modules/output/002-network.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
loader="$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2"

[[ -f "$artifact" ]] || die "network module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

mapfile -d '' library_directories < <(
    find "$module_root" -type f -name '*.so.*' -printf '%h\0' | sort -zu
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
    [[ -n "$command" ]] || die "network command is unavailable: $name"
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" "$command" "$@" >/dev/null
}

run_command mtr --version
run_command traceroute --version
run_command tcpdump --version
run_command iperf3 --version
run_command nmap --version
run_command ncat --version
run_command nping --version

nmap_binary=$(find "$module_root" -type f -name nmap -perm -0100 -print -quit)
nmap_data=$(find "$module_root" -type d -path '*/share/nmap' -print -quit)
[[ -n "$nmap_binary" && -n "$nmap_data" ]] || die "Nmap runtime is incomplete"
env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    "$loader" --library-path "$library_path" \
    "$nmap_binary" --datadir "$nmap_data" --script-help default >/dev/null

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

print(f"network module ELF closure: {len(elf_files)} files")
PY

size=$(stat -c %s "$artifact")
(( size <= 32 * 1024 * 1024 )) || die "network module exceeds 32 MiB: $size"
sha256sum "$artifact"
log "Network commands, Nmap data, ELF closure, and size budget passed ($size bytes)"
