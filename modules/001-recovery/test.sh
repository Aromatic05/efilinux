#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command python3 readelf sha256sum timeout unsquashfs

artifact="$MODULE_DIR/build/output/001-recovery.zxm"
work="$MODULE_DIR/build/test/artifact"
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
bc	1.08.2
bzip2	1.0.8
chntpw	140201
cifs-utils	7.7
clonezilla	5.16.25
dialog	1.3-20260721
dislocker	0.7.3
drbl-runtime	5.9.11
foremost	1.5.7
fsarchiver	0.8.9
fuse2	2.9.9
jq	1.8.2
krb5	1.22.2
libaio	0.3.113
libevent	2.1.12-stable
libldm	0.2.5
libtirpc	1.3.7
lvm2	2.03.41
lz4	1.10.0
mbedtls2	2.28.10
nbd	3.24
netcat-traditional	1.10-50
nfs-utils	2.9.1
partclone	0.3.47
qemu-img	11.0.3
rpcbind	1.2.9
sleuthkit	4.15.0
sshfs	3.7.6
talloc	2.4.4
testdisk	7.2
wimlib	1.14.5
PACKAGES

tail -n +2 "$module_root/opt/efilinux/modules/recovery/packages.tsv" |
    LC_ALL=C sort > "$work/actual-packages"
cmp -s "$work/expected-packages" "$work/actual-packages" ||
    die "recovery module package manifest differs from the expected self-contained set"

for command in \
    testdisk photorec fsarchiver partclone.info foremost fls tsk_recover \
    wimlib-imagex ldmtool dislocker dislocker-fuse sshfs mount.sshfs \
    chntpw reged samusrgrp sampasswd samunlock \
    mount.cifs mount.smb3 cifs.upcall cifscreds getcifsacl setcifsacl smbinfo \
    kinit klist qemu-img qemu-nbd nbd-client \
    mount.nfs mount.nfs4 umount.nfs umount.nfs4 showmount nfsstat \
    rpc.statd sm-notify start-statd rpc.gssd rpc.idmapd nfsidmap \
    rpcbind rpcinfo \
    lvm lvs pvs vgs vgchange lvchange lvcreate pvcreate \
    bc dc dialog jq nc.traditional \
    clonezilla ocs-sr ocs-onthefly ocs-chkimg ocs-live-ver; do
    [[ -x "$module_root/usr/bin/$command" ]] ||
        die "recovery module command is missing: $command"
done

for config in netconfig nfs.conf nfsmount.conf idmapd.conf; do
    [[ -f "$module_root/opt/efilinux/modules/recovery/etc/$config" ]] ||
        die "recovery module NFS configuration is missing: $config"
done
grep -aFq '/opt/efilinux/modules/recovery/etc/netconfig' \
    "$module_root/usr/lib/libtirpc.so.3"

for config in drbl.conf drbl-ocs.conf; do
    [[ -f "$module_root/opt/efilinux/modules/recovery/etc/drbl/$config" ]] ||
        die "Clonezilla module configuration is missing: $config"
done
for library in drbl-conf-functions drbl-functions ocs-functions; do
    [[ -f "$module_root/opt/efilinux/modules/recovery/share/drbl/sbin/$library" ]] ||
        die "Clonezilla runtime function library is missing: $library"
done
if grep -RIlE '/usr/share/drbl|/etc/drbl|/etc/ocs' \
        "$module_root/usr/bin" \
        "$module_root/opt/efilinux/modules/recovery/share/drbl" \
        | grep -q .; then
    die "Clonezilla payload still references host-global DRBL paths"
fi
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

while IFS= read -r script; do
    run_target "$EFILINUX_ROOTFS/usr/bin/bash" -n "$script"
done < <(find \
    "$module_root/usr/bin" \
    "$module_root/opt/efilinux/modules/recovery/share/drbl" \
    -type f -exec grep -Il '^#!.*bash' {} +)

MODULE_ROOT="$module_root" \
DRBL_SCRIPT_PATH="$module_root/opt/efilinux/modules/recovery/share/drbl" \
DRBL_CONFIG_DIR="$module_root/opt/efilinux/modules/recovery/etc/drbl" \
    run_target "$EFILINUX_ROOTFS/usr/bin/bash" -c '
        set -e
        . "$DRBL_SCRIPT_PATH/sbin/drbl-conf-functions"
        . "$DRBL_SCRIPT_PATH/sbin/ocs-functions"
        type check_if_root >/dev/null
        type USAGE_common_save >/dev/null
    '

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
chntpw_output=$(run_target "$module_root/usr/bin/chntpw" 2>&1 || true)
grep -Fq 'chntpw version 1.00 140201' <<<"$chntpw_output"
run_target "$module_root/usr/bin/cifs.upcall" --version 2>&1 |
    grep -Fxq 'version: 7.7'
run_target "$module_root/usr/bin/klist" -V 2>&1 |
    grep -Fxq 'Kerberos 5 version 1.22.2'
run_target "$module_root/usr/bin/qemu-img" --version 2>&1 |
    grep -Fq 'qemu-img version 11.0.3'
run_target "$module_root/usr/bin/nbd-client" --version 2>&1 |
    grep -Fq 'This is nbd-client, from nbd 3.24'
run_target "$module_root/usr/bin/lvm" version 2>&1 |
    grep -Fq 'LVM version:     2.03.41'
run_target "$module_root/usr/bin/bc" --version 2>&1 |
    grep -Fq 'bc 1.08.2'
run_target "$module_root/usr/bin/dialog" --version 2>&1 |
    grep -Fxq 'Version: 1.3-20260721'
run_target "$module_root/usr/bin/jq" --version 2>&1 |
    grep -Fxq 'jq-1.8.2'
run_target "$module_root/usr/bin/nc.traditional" -h 2>&1 |
    grep -Fq '[v1.10-50]'

netcat_port=$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)
netcat_received="$work/netcat-received"
timeout 5 \
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    "$loader" --library-path "$library_path" \
    "$module_root/usr/bin/nc.traditional" -l -p "$netcat_port" \
    > "$netcat_received" &
netcat_listener=$!
sleep 0.2
printf '%s\n' 'efilinux-netcat-ok' |
    timeout 5 \
        env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" \
        "$module_root/usr/bin/nc.traditional" -q 0 127.0.0.1 "$netcat_port"
wait "$netcat_listener"
grep -Fxq 'efilinux-netcat-ok' "$netcat_received"

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
