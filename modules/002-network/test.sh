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
library_path="$module_root/usr/lib:$EFILINUX_ROOTFS/usr/lib"

[[ -f "$artifact" ]] || die "network module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

grep -Fxq 'format=1' "$image/metadata/manifest"
grep -Fxq 'id=network' "$image/metadata/manifest"
grep -Fxq 'arch=x86_64' "$image/metadata/manifest"
grep -Fxq 'version=1' "$image/metadata/manifest"

cat > "$work/expected-packages" <<'PACKAGES'
iperf3	3.21
libpcap	1.10.6
mtr	0.96
nmap	7.99
tcpdump	4.99.6
traceroute	2.1.6
PACKAGES

tail -n +2 "$module_root/opt/efilinux/modules/network/packages.tsv" |
    LC_ALL=C sort > "$work/actual-packages"
cmp -s "$work/expected-packages" "$work/actual-packages" ||
    die "network module package manifest differs from the expected self-contained set"

for command in mtr mtr-packet traceroute tcpdump iperf3 nmap ncat nping; do
    [[ -x "$module_root/usr/bin/$command" ]] ||
        die "network module command is missing: $command"
done

for data in nmap-services nmap-service-probes nmap-os-db nmap-protocols; do
    [[ -s "$module_root/usr/share/nmap/$data" ]] ||
        die "Nmap runtime data is missing: $data"
done
[[ -d "$module_root/usr/share/nmap/scripts" ]] || die "Nmap NSE scripts are missing"
[[ -d "$module_root/usr/share/nmap/nselib" ]] || die "Nmap NSE libraries are missing"
(( $(find "$module_root/usr/share/nmap/scripts" -type f -name '*.nse' | wc -l) >= 500 )) ||
    die "Nmap NSE script set is unexpectedly incomplete"

if find "$module_root" \
        \( -path '*/include/*' -o -path '*/lib/pkgconfig/*' \
           -o -path '*/share/man/*' -o -path '*/share/doc/*' \
           -o -name '*.a' -o -name '*.la' \) \
        -print -quit | grep -q .; then
    die "network module contains development, static, or documentation payload"
fi

run_target() {
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" "$@"
}

run_target "$module_root/usr/bin/mtr" --version 2>&1 |
    grep -Fq 'mtr 0.96'
run_target "$module_root/usr/bin/traceroute" --version 2>&1 |
    grep -Fq 'Modern traceroute for Linux, version 2.1.6'
run_target "$module_root/usr/bin/tcpdump" --version 2>&1 |
    grep -Fq 'tcpdump version 4.99.6'
run_target "$module_root/usr/bin/iperf3" --version 2>&1 |
    grep -Fq 'iperf 3.21'
run_target "$module_root/usr/bin/nmap" --version 2>&1 |
    grep -Fq 'Nmap version 7.99'
run_target "$module_root/usr/bin/ncat" --version 2>&1 |
    grep -Fq 'Ncat: Version 7.99'
run_target "$module_root/usr/bin/nping" --version 2>&1 |
    grep -Fq 'Nping version 0.7.99'

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

print(f"network module ELF closure: {elf_count} files")
PY

size=$(stat -c %s "$artifact")
(( size <= 32 * 1024 * 1024 )) ||
    die "network module exceeds 32 MiB: $size"
sha256sum "$artifact"
log "Network module commands, data, package manifest, ELF closure, and payload policy passed ($size bytes)"
