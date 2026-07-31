#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command python3 readelf

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"

rootfs_owner() {
    local path=$1
    awk -F '\t' -v path="$path" \
        'NR > 1 && $1 == path && $2 != "directory" { print $3; exit }' \
        "$EFILINUX_ROOTFS_OWNERS"
}

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
    dconf fusermount3 \
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
    libntfs-3g.so.90 \
    libncursesw.so.6 libreadline.so.8 libhistory.so.8 \
    libduktape.so.207 liblua.so.5.4 libasound.so.2 \
    libell.so.0 libndp.so.0 \
    libarchive.so.13 libfuse3.so.4 libsqlite3.so.0 libdconf.so.1 \
    libgpg-error.so.0 libgcrypt.so.20 libsecret-1.so.0 \
    libgmp.so.10 libmpfr.so.6 libjson-c.so.5 libpopt.so.0 \
    libkeyutils.so.1 libsndfile.so.1; do
    [[ -e "$rootfs/usr/lib/$library" ]] || die "runtime library is missing: $library"
done

[[ ! -e "$rootfs/usr/lib/libsqlite3.so" ]] || \
    die "SQLite development linker name leaked into the runtime rootfs"
sqlite_runtime=$(readlink -f "$rootfs/usr/lib/libsqlite3.so.0")
LC_ALL=C readelf -d "$sqlite_runtime" | \
    grep -Fq 'Library soname: [libsqlite3.so.0]' || \
    die "SQLite runtime library does not declare libsqlite3.so.0 as its SONAME"

for data_file in \
    /etc/protocols \
    /etc/services \
    /usr/share/zoneinfo/UTC; do
    [[ -f "$rootfs$data_file" ]] || die "runtime data is missing: $data_file"
done

for dconf_file in \
    /usr/lib/gio/modules/libdconfsettings.so \
    /usr/libexec/dconf-service \
    /usr/share/dbus-1/services/ca.desrt.dconf.service; do
    [[ -e "$rootfs$dconf_file" ]] || die "dconf runtime component is missing: $dconf_file"
done
if grep -Fq 'SystemdService=' \
    "$rootfs/usr/share/dbus-1/services/ca.desrt.dconf.service"; then
    die "dconf D-Bus activation still requires systemd"
fi

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

run_target() {
    local program=$1
    shift
    "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/$program" "$@"
}

run_filesystem_command() {
    local log_file=$1
    local description=$2
    shift 2

    if ! run_target "$@" > "$log_file" 2>&1; then
        cat "$log_file" >&2
        die "$description failed"
    fi
}

filesystem_test_directory="$EFILINUX_TEST/filesystems"
reset_directory "$filesystem_test_directory"

truncate -s 64M "$filesystem_test_directory/ext4.img"
run_filesystem_command "$filesystem_test_directory/ext4-mkfs.log" \
    "ext4 creation" mke2fs -q -t ext4 -F "$filesystem_test_directory/ext4.img"
run_filesystem_command "$filesystem_test_directory/ext4-check.log" \
    "ext4 read-only check" e2fsck -fn "$filesystem_test_directory/ext4.img"

truncate -s 256M "$filesystem_test_directory/btrfs.img"
run_filesystem_command "$filesystem_test_directory/btrfs-mkfs.log" \
    "Btrfs creation" mkfs.btrfs -q -f "$filesystem_test_directory/btrfs.img"
run_filesystem_command "$filesystem_test_directory/btrfs-check.log" \
    "Btrfs read-only check" btrfs check --readonly "$filesystem_test_directory/btrfs.img"

truncate -s 512M "$filesystem_test_directory/xfs.img"
run_filesystem_command "$filesystem_test_directory/xfs-mkfs.log" \
    "XFS creation" mkfs.xfs -q -f "$filesystem_test_directory/xfs.img"
run_filesystem_command "$filesystem_test_directory/xfs-check.log" \
    "XFS read-only check" xfs_repair -n "$filesystem_test_directory/xfs.img"

truncate -s 64M "$filesystem_test_directory/fat.img"
run_filesystem_command "$filesystem_test_directory/fat-mkfs.log" \
    "FAT creation" mkfs.fat "$filesystem_test_directory/fat.img"
run_filesystem_command "$filesystem_test_directory/fat-check.log" \
    "FAT read-only check" fsck.fat -n "$filesystem_test_directory/fat.img"

truncate -s 64M "$filesystem_test_directory/exfat.img"
run_filesystem_command "$filesystem_test_directory/exfat-mkfs.log" \
    "exFAT creation" mkfs.exfat "$filesystem_test_directory/exfat.img"
run_filesystem_command "$filesystem_test_directory/exfat-check.log" \
    "exFAT read-only check" fsck.exfat -n "$filesystem_test_directory/exfat.img"

truncate -s 128M "$filesystem_test_directory/ntfs.img"
run_filesystem_command "$filesystem_test_directory/ntfs-mkfs.log" \
    "NTFS creation" mkntfs -F -Q "$filesystem_test_directory/ntfs.img"
run_filesystem_command "$filesystem_test_directory/ntfs-check.log" \
    "NTFS read-only check" ntfsfix -n "$filesystem_test_directory/ntfs.img"

python3 - "$rootfs" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(sys.argv[1])
missing: list[tuple[str, str]] = []

def expand_search_directory(artifact: Path, value: str) -> Path:
    origin = artifact.parent
    value = value.replace("${ORIGIN}", str(origin)).replace("$ORIGIN", str(origin))
    path = Path(value)
    if path.is_absolute():
        try:
            relative = path.relative_to(root)
        except ValueError:
            relative = Path(str(path).lstrip("/"))
        return root / relative
    return origin / path

for artifact in sorted(root.rglob("*")):
    if artifact.is_symlink() or not artifact.is_file():
        continue
    result = subprocess.run(
        ["readelf", "-d", str(artifact)],
        text=True,
        capture_output=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    if result.returncode:
        continue

    search_directories = [root / "usr/lib", root / "lib"]
    for encoded_path in re.findall(
        r"Library (?:runpath|rpath): \[(.*?)\]", result.stdout, re.IGNORECASE
    ):
        for entry in encoded_path.split(":"):
            if entry:
                search_directories.append(expand_search_directory(artifact, entry))

    for soname in re.findall(r"Shared library: \[(.*?)\]", result.stdout):
        if not any((directory / soname).exists() for directory in search_directories):
            missing.append((str(artifact.relative_to(root)), soname))

if missing:
    for artifact, soname in missing:
        print(f"{artifact}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)
PY

require_runtime_library() {
    local pattern=$1
    local owner=$2
    local file

    shopt -s nullglob
    for file in "$rootfs/usr/lib"/$pattern; do
        [[ $(rootfs_owner "/usr/lib/$(basename -- "$file")") == "$owner" ]] || \
            die "$(basename -- "$file") is not owned by $owner"
        shopt -u nullglob
        return
    done
    shopt -u nullglob
    die "runtime library family is missing: $pattern"
}

require_runtime_library 'libgcc_s.so.1*' gcc-libs
require_runtime_library 'libstdc++.so.6*' gcc-libs
require_runtime_library 'libffi.so.8*' libffi
require_runtime_library 'libpcre2-8.so.0*' pcre2

for compiler in gcc g++ cc c++ cpp gcov; do
    [[ ! -e "$rootfs/usr/bin/$compiler" ]] || \
        die "compiler executable leaked into target rootfs: $compiler"
done

if find "$rootfs/usr/lib" -type f -name '*-gdb.py' -print -quit | grep -q .; then
    die "GDB pretty-printer scripts leaked into target rootfs"
fi

if find "$rootfs" -type f \( -name '*.a' -o -name '*.la' -o -name '*.pc' \) \
    -print -quit | grep -q .; then
    die "development artifact leaked into target rootfs"
fi
[[ ! -d "$rootfs/usr/include" ]] || die "target headers leaked into rootfs"

if awk -F '\t' 'NR > 1 && $2 != "directory" { count[$1]++ } END { for (path in count) if (count[path] > 1) exit 1 }' \
    "$EFILINUX_ROOTFS_OWNERS"; then
    :
else
    die "rootfs ownership manifest contains duplicate paths"
fi

log "Runtime tools, filesystem round trips, and full rootfs ELF closure passed"
