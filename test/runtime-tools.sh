#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command python3 readelf

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"

require_formal_program() {
    local name=$1
    local path="$rootfs/usr/bin/$name"

    [[ -x "$path" ]] || die "runtime tool is missing: $name"
    if [[ -L "$path" && $(readlink -- "$path") == busybox ]]; then
        die "BusyBox still owns formal runtime tool: $name"
    fi
}

for program in \
    depmod insmod lsmod modinfo modprobe rmmod \
    mount umount findmnt lsblk blkid hwclock swapon swapoff \
    fdisk sfdisk wipefs rfkill \
    e2fsck mke2fs mkfs.ext4 resize2fs tune2fs dumpe2fs \
    loadkeys setfont \
    btrfs mkfs.btrfs \
    xfs_repair mkfs.xfs \
    fsck.fat mkfs.fat \
    fsck.exfat mkfs.exfat \
    ntfsfix mkntfs ntfsresize; do
    require_formal_program "$program"
done

for library in \
    libattr.so.1 libacl.so.1 libcap.so.2 libcrypt.so.2 libkmod.so.2 \
    libblkid.so.1 libmount.so.1 libuuid.so.1 liblzo2.so.2 \
    libext2fs.so.2 libinih.so.0 liburcu.so.8 libhandle.so.1 \
    libntfs-3g.so.90; do
    [[ -e "$rootfs/usr/lib/$library" ]] || die "runtime library is missing: $library"
done

for data_file in \
    /etc/protocols \
    /etc/services \
    /usr/share/zoneinfo/UTC; do
    [[ -f "$rootfs$data_file" ]] || die "runtime data is missing: $data_file"
done

[[ -L "$rootfs/etc/localtime" ]] || die "/etc/localtime is not a symbolic link"
[[ $(readlink -- "$rootfs/etc/localtime") == /usr/share/zoneinfo/UTC ]] || \
    die "/etc/localtime does not default to UTC"

"$loader" --library-path "$library_path" "$rootfs/usr/bin/modinfo" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/findmnt" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/btrfs" version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/xfs_repair" -V >/dev/null
set +e
exfat_version=$(
    "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/mkfs.exfat" -V 2>&1
)
exfat_status=$?
set -e
[[ "$exfat_status" -eq 1 && "$exfat_version" == *"exfatprogs version"* ]] || \
    die "mkfs.exfat version probe failed"
"$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/ntfsfix" --help >/dev/null 2>&1

python3 - "$rootfs" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(sys.argv[1])
library_directory = root / "usr/lib"
missing: list[tuple[str, str]] = []

for program in sorted((root / "usr/bin").iterdir()):
    if not program.is_file() or program.is_symlink():
        continue
    result = subprocess.run(
        ["readelf", "-d", str(program)],
        text=True,
        capture_output=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    if result.returncode:
        continue
    for soname in re.findall(r"Shared library: \[(.*?)\]", result.stdout):
        if not (library_directory / soname).exists():
            missing.append((program.name, soname))

if missing:
    for program, soname in missing:
        print(f"{program}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)
PY

if find "$rootfs" -type f \( -name '*.a' -o -name '*.la' -o -name '*.pc' \) \
    -print -quit | grep -q .; then
    die "development artifact leaked into target rootfs"
fi
[[ ! -d "$rootfs/usr/include" ]] || die "target headers leaked into rootfs"

if awk -F '\t' '{ count[$1]++ } END { for (path in count) if (count[path] > 1) exit 1 }' \
    "$EFILINUX_ROOTFS_OWNERS"; then
    :
else
    die "rootfs ownership manifest contains duplicate paths"
fi

log "001-runtime maintenance tools and filesystem policy passed"
