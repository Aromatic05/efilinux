#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command python3 readelf sha256sum unsquashfs

artifact="$MODULE_DIR/output/001-recovery.zxm"
work="$MODULE_DIR/test/artifact"
image="$work/image"
module_root="$image/root"
loader="$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2"
library_path="$module_root/usr/lib:$EFILINUX_ROOTFS/usr/lib"

[[ -f "$artifact" ]] || die "recovery module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

grep -Fxq 'format=1' "$image/metadata/manifest"
grep -Fxq 'id=recovery' "$image/metadata/manifest"
grep -Fxq 'arch=x86_64' "$image/metadata/manifest"
grep -Fxq 'version=1' "$image/metadata/manifest"

cat > "$work/expected-packages" <<'PACKAGES'
bzip2	1.0.8
dislocker	0.7.3
foremost	1.5.7
fsarchiver	0.8.9
fuse2	2.9.9
libldm	0.2.5
lz4	1.10.0
mbedtls2	2.28.10
partclone	0.3.47
sleuthkit	4.15.0
sshfs	3.7.6
testdisk	7.2
wimlib	1.14.5
PACKAGES

tail -n +2 "$module_root/opt/efilinux/modules/recovery/packages.tsv" |
    LC_ALL=C sort > "$work/actual-packages"
cmp -s "$work/expected-packages" "$work/actual-packages" ||
    die "recovery module package manifest differs from the expected self-contained set"

for command in \
    testdisk photorec fsarchiver partclone.info foremost fls tsk_recover \
    wimlib-imagex ldmtool dislocker dislocker-fuse sshfs mount.sshfs; do
    [[ -x "$module_root/usr/bin/$command" ]] ||
        die "recovery module command is missing: $command"
done

if find "$module_root" \
        \( -path '*/include/*' -o -path '*/lib/pkgconfig/*' \
           -o -path '*/share/man/*' -o -path '*/share/doc/*' \
           -o -path "$module_root/etc" -o -path "$module_root/etc/*" \) \
        -print -quit | grep -q .; then
    die "recovery module contains development, documentation, or /etc payload"
fi

run_target() {
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" "$@"
}

run_target "$module_root/usr/bin/testdisk" /version 2>&1 |
    grep -Fq 'Version: 7.2'
run_target "$module_root/usr/bin/fsarchiver" --version 2>&1 |
    grep -Fq 'fsarchiver 0.8.9'
run_target "$module_root/usr/bin/partclone.info" -v 2>&1 |
    grep -Fq 'Partclone : v0.3.47'
run_target "$module_root/usr/bin/foremost" -V 2>&1 |
    grep -Fxq '1.5.7'
run_target "$module_root/usr/bin/fls" -V 2>&1 |
    grep -Fq 'The Sleuth Kit ver 4.15.0'
run_target "$module_root/usr/bin/wimlib-imagex" --version 2>&1 |
    grep -Fq 'wimlib-imagex 1.14.5 (using wimlib 1.14.5)'
run_target "$module_root/usr/bin/ldmtool" --help 2>&1 |
    grep -Fq 'Available commands:'
run_target "$module_root/usr/bin/dislocker" -h 2>&1 |
    grep -Fq 'v0.7.3'
run_target "$module_root/usr/bin/sshfs" --version 2>&1 |
    grep -Fq 'SSHFS version 3.7.6'

python3 - "$module_root" "$EFILINUX_ROOTFS" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

module_root = Path(sys.argv[1])
base_root = Path(sys.argv[2])
library_directories = [module_root / "usr/lib", base_root / "usr/lib"]
missing = []
elf_count = 0

for root in (module_root / "usr/bin", module_root / "usr/lib"):
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        if path.read_bytes()[:4] != b"\x7fELF":
            continue
        elf_count += 1
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

print(f"recovery module ELF closure: {elf_count} files")
PY

size=$(stat -c %s "$artifact")
(( size <= 64 * 1024 * 1024 )) ||
    die "recovery module exceeds 64 MiB: $size"
sha256sum "$artifact"
log "Recovery module commands, package manifest, ELF closure, and payload policy passed ($size bytes)"
