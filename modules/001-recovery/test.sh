#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command bwrap openssl python3 readelf sha256sum timeout unsquashfs

artifact="$ROOT/modules/output/001-recovery.zxm"
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
perl-runtime	5.44.0
qemu-img	11.0.3
rpcbind	1.2.9
sleuthkit	4.15.0
sshfs	3.7.6
talloc	2.4.4
testdisk	7.2
wget	1.25.0
wimlib	1.14.5
PACKAGES

tail -n +2 "$module_root/opt/efilinux/modules/recovery/packages.tsv" |
    LC_ALL=C sort > "$work/actual-packages"
cmp -s "$work/expected-packages" "$work/actual-packages" ||
    die "recovery module package manifest differs from the expected self-contained set"

for command in \
    testdisk photorec fsarchiver partclone.info foremost fls tsk_recover sorter mactime \
    wimlib-imagex ldmtool dislocker dislocker-fuse sshfs mount.sshfs \
    chntpw reged samusrgrp sampasswd samunlock \
    mount.cifs mount.smb3 cifs.upcall cifscreds getcifsacl setcifsacl smbinfo \
    kinit klist qemu-img qemu-nbd nbd-client \
    mount.nfs mount.nfs4 umount.nfs umount.nfs4 showmount nfsstat \
    rpc.statd sm-notify start-statd rpc.gssd rpc.idmapd nfsidmap \
    rpcbind rpcinfo \
    lvm lvs pvs vgs vgchange lvchange lvcreate pvcreate \
    bc dc dialog jq nc.traditional wget \
    clonezilla ocs-sr ocs-onthefly ocs-chkimg ocs-live-ver; do
    [[ -x "$module_root/usr/bin/$command" ]] ||
        die "recovery module command is missing: $command"
done
[[ ! -e "$module_root/usr/bin/ocsmgrd" ]] ||
    die "unsupported Clonezilla management daemon leaked into the recovery module"

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
private_perl=/opt/efilinux/modules/recovery/perl/bin/perl
[[ -x "$module_root$private_perl" ]] ||
    die "private recovery Perl runtime is missing"
[[ ! -e "$module_root/usr/bin/perl" ]] ||
    die "recovery module must not claim the global /usr/bin/perl path"
if grep -RIlE '^#!/usr/bin/(env[[:space:]]+)?perl' \
        "$module_root/usr/bin" \
        "$module_root/opt/efilinux/modules/recovery/share/drbl" \
        | grep -q .; then
    die "Clonezilla payload still contains a global Perl shebang"
fi
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

run_sandbox() {
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        bwrap \
        --unshare-all \
        --share-net \
        --die-with-parent \
        --tmpfs / \
        --dir /usr \
        --ro-bind "$EFILINUX_ROOTFS/usr" /usr \
        --symlink usr/bin /bin \
        --symlink usr/lib /lib \
        --symlink usr/lib /lib64 \
        --dir /etc \
        --ro-bind "$EFILINUX_ROOTFS/etc" /etc \
        --dir /opt \
        --ro-bind "$module_root/opt" /opt \
        --ro-bind "$module_root" /module \
        --ro-bind "$work" /test-work \
        --dev /dev \
        --proc /proc \
        --tmpfs /tmp \
        --dir /run \
        --dir /var \
        --chdir / \
        "$@"
}

while IFS= read -r script; do
    run_target "$EFILINUX_ROOTFS/usr/bin/bash" -n "$script"
done < <(find \
    "$module_root/usr/bin" \
    "$module_root/opt/efilinux/modules/recovery/share/drbl" \
    -type f -exec grep -Il '^#!.*bash' {} +)

run_sandbox \
    /usr/bin/env \
    DRBL_SCRIPT_PATH=/opt/efilinux/modules/recovery/share/drbl \
    DRBL_CONFIG_DIR=/opt/efilinux/modules/recovery/etc/drbl \
    /usr/bin/bash -c '
        set +e
        . "$DRBL_SCRIPT_PATH/sbin/drbl-conf-functions"
        conf_status=$?
        . "$DRBL_SCRIPT_PATH/sbin/ocs-functions"
        ocs_status=$?
        test "$conf_status" -eq 0
        test "$ocs_status" -eq 0
        test "$(command -v perl)" = /opt/efilinux/modules/recovery/perl/bin/perl
        type check_if_root >/dev/null
        type USAGE_common_save >/dev/null
    '

run_sandbox "$private_perl" \
    -V:version \
    -V:archname \
    -V:useithreads \
    -V:useshrplib \
    -V:gnulibc_version 2>&1 |
    grep -Fq "gnulibc_version='2.43'"
run_sandbox "$private_perl" \
    -MData::Dumper \
    -MDigest::SHA \
    -MEncode \
    -MFile::Copy \
    -MFile::Path \
    -MFile::Temp \
    -MGetopt::Std \
    -MIO::Select \
    -MIO::Socket \
    -MJSON::PP \
    -MMIME::Base64 \
    -MMath::BigInt \
    -MPOSIX \
    -MSocket \
    -MTerm::ANSIColor \
    -e 'print qq(recovery-perl-modules-ok\n)' |
    grep -Fxq 'recovery-perl-modules-ok'

while IFS= read -r script; do
    relative=${script#"$module_root"}
    run_sandbox "$private_perl" -c "/module$relative" >/dev/null
done < <(grep -RIl '^#!/opt/efilinux/modules/recovery/perl/bin/perl' \
    "$module_root/usr/bin" \
    "$module_root/opt/efilinux/modules/recovery/share/drbl")

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
run_target "$module_root/usr/bin/wget" --version 2>&1 |
    grep -Fq 'GNU Wget 1.25.0'
if run_target "$module_root/usr/bin/wget" --version 2>&1 |
        grep -Eq '^(Compile|Link):'; then
    die "Wget exposes non-reproducible compiler or linker command lines"
fi
if grep -aFq "$ROOT" "$module_root/usr/bin/wget"; then
    die "Wget contains the host repository path"
fi

wget_config="$module_root/opt/efilinux/modules/recovery/etc/wget/wgetrc"
wget_ca="$module_root/opt/efilinux/modules/recovery/share/ca-certificates/cacert.pem"
[[ -f "$wget_config" && -f "$wget_ca" ]] ||
    die "Wget configuration or CA bundle is missing"
grep -Fxq \
    'ca_certificate = /opt/efilinux/modules/recovery/share/ca-certificates/cacert.pem' \
    "$wget_config"
grep -Fxq 'check_certificate = on' "$wget_config"
[[ $(grep -c '^-----BEGIN CERTIFICATE-----$' "$wget_ca") == 119 ]] ||
    die "Wget CA bundle certificate count changed"
printf '%s  %s\n' \
    3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91 \
    "$wget_ca" |
    sha256sum --check --status
openssl crl2pkcs7 -nocrl -certfile "$wget_ca" |
    openssl pkcs7 -print_certs -noout >/dev/null
grep -aFq '/opt/efilinux/modules/recovery/etc/wget/wgetrc' \
    "$module_root/usr/bin/wget"

tls_dir="$work/tls"
mkdir -p "$tls_dir"
printf '%s\n' 'efilinux-wget-tls-ok' > "$tls_dir/index.html"
openssl req \
    -x509 \
    -newkey rsa:2048 \
    -nodes \
    -days 1 \
    -subj '/CN=EFILinux Recovery Test CA' \
    -keyout "$tls_dir/ca.key" \
    -out "$tls_dir/ca.pem" \
    >/dev/null 2>&1
openssl req \
    -newkey rsa:2048 \
    -nodes \
    -subj '/CN=localhost' \
    -keyout "$tls_dir/server.key" \
    -out "$tls_dir/server.csr" \
    >/dev/null 2>&1
cat > "$tls_dir/server.ext" <<'TLS_EXT'
subjectAltName=DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
TLS_EXT
openssl x509 \
    -req \
    -days 1 \
    -in "$tls_dir/server.csr" \
    -CA "$tls_dir/ca.pem" \
    -CAkey "$tls_dir/ca.key" \
    -CAcreateserial \
    -extfile "$tls_dir/server.ext" \
    -out "$tls_dir/server.pem" \
    >/dev/null 2>&1
tls_port=$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)
(
    cd "$tls_dir"
    exec openssl s_server \
        -accept "127.0.0.1:$tls_port" \
        -cert server.pem \
        -key server.key \
        -WWW \
        -quiet
) > "$tls_dir/server.log" 2>&1 &
tls_server=$!
cleanup_tls_server() {
    kill "$tls_server" 2>/dev/null || true
    wait "$tls_server" 2>/dev/null || true
}
trap cleanup_tls_server EXIT
tls_ready=false
for _ in {1..50}; do
    if (echo > "/dev/tcp/127.0.0.1/$tls_port") 2>/dev/null; then
        tls_ready=true
        break
    fi
    sleep 0.05
done
[[ $tls_ready == true ]] || die "local Wget TLS test server did not start"

if run_sandbox \
        /module/usr/bin/wget \
        --quiet \
        --timeout=3 \
        --tries=1 \
        --output-document=- \
        "https://127.0.0.1:$tls_port/index.html" \
        > "$tls_dir/untrusted.out" \
        2> "$tls_dir/untrusted.err"; then
    die "Wget accepted a certificate outside the configured trust store"
fi
run_sandbox \
    /module/usr/bin/wget \
    --quiet \
    --timeout=5 \
    --tries=1 \
    --ca-certificate=/test-work/tls/ca.pem \
    --output-document=- \
    "https://127.0.0.1:$tls_port/index.html" |
    grep -Fxq 'efilinux-wget-tls-ok'
cleanup_tls_server
trap - EXIT

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
module_library_names = {
    path.name
    for path in module_root.rglob("*")
    if path.is_file() or path.is_symlink()
}
missing = []
glibc_too_new = []
elf_count = 0

for root in (module_root / "usr/bin", module_root / "usr/lib", module_root / "opt"):
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
            if soname not in module_library_names and not any(
                (directory / soname).exists() for directory in library_directories
            ):
                missing.append((path, soname))
        version_result = subprocess.run(
            ["readelf", "--version-info", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        for major, minor in re.findall(r"GLIBC_(\d+)\.(\d+)", version_result.stdout):
            version = (int(major), int(minor))
            if version > (2, 43):
                glibc_too_new.append((path, version))

if missing:
    for path, soname in missing:
        print(f"{path}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)

if glibc_too_new:
    for path, version in sorted(set(glibc_too_new)):
        print(f"{path}: requires GLIBC_{version[0]}.{version[1]}", file=sys.stderr)
    raise SystemExit(1)

print(f"recovery module ELF closure: {elf_count} files, maximum GLIBC_2.43")
PY

size=$(stat -c %s "$artifact")
(( size <= 64 * 1024 * 1024 )) ||
    die "recovery module exceeds 64 MiB: $size"
sha256sum "$artifact"
log "Recovery module commands, package manifest, ELF closure, and payload policy passed ($size bytes)"
