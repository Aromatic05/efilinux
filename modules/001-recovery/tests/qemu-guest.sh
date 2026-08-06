#!/usr/bin/sh

set -eu

module_path=/mnt/001-recovery.zxm
private_perl=/opt/recovery/perl/bin/perl

fail() {
    printf 'EFILINUX_RECOVERY_FAIL:%s\n' "$1"
    /usr/bin/findmnt -R /run/zxmod 2>/dev/null || true
    /usr/bin/losetup --all 2>/dev/null || true
    poweroff -f
    exit 1
}

stage() {
    printf 'EFILINUX_RECOVERY_STAGE:%s\n' "$1"
}

module_loop_is_present() {
    /usr/bin/losetup --associated "$module_path" 2>/dev/null |
        /usr/bin/grep -q .
}

wait_for_module_loop_release() {
    recovery_wait=0
    while module_loop_is_present; do
        [ "$recovery_wait" -lt 10 ] || break
        sleep 1
        recovery_wait=$((recovery_wait + 1))
    done
    if module_loop_is_present; then
        recovery_loop_line=$(/usr/bin/losetup --associated "$module_path" 2>/dev/null |
            sed -n '1p')
        recovery_loop=${recovery_loop_line%%:*}
        recovery_autoclear=$(/usr/bin/losetup --noheadings --output AUTOCLEAR \
            "$recovery_loop" 2>/dev/null | tr -d '[:space:]')
        [ "$recovery_autoclear" = 1 ] || fail module-loop-leaked
        printf 'EFILINUX_RECOVERY_LOOP_AUTOCLEAR=%s\n' "$recovery_loop"
    fi
}

module_mount_count() {
    /usr/bin/awk '
        $5 == "/usr" || $5 == "/opt" || index($5, "/run/zxmod/") == 1 {
            count++
        }
        END { print count + 0 }
    ' /proc/self/mountinfo
}

expect_output() {
    expected=$1
    shift
    command_name=$1
    command_status=0
    command_output=$("$@" 2>&1) || command_status=$?
    if [ "$command_status" -ne 0 ]; then
        printf 'EFILINUX_RECOVERY_COMMAND:%s:status=%s\n%s\n' \
            "$command_name" "$command_status" "$command_output"
        fail "command-status:$command_name"
    fi
    case $command_output in
        *"$expected"*) ;;
        *)
            printf 'EFILINUX_RECOVERY_COMMAND:%s:expected=%s\n%s\n' \
                "$command_name" "$expected" "$command_output"
            fail "command-output:$command_name"
            ;;
    esac
}

stage start
[ "$(id -u)" = 0 ] || fail not-root
[ -f "$module_path" ] || fail module-missing
[ ! -e /usr/bin/clonezilla ] || fail clonezilla-present-before-load
[ ! -e /opt/recovery/bin/qphotorec ] || fail qphotorec-present-before-load
[ ! -e /opt/recovery/bin/nmtui ] || fail nmtui-present-before-load
[ ! -e /usr/share/applications/recovery-qphotorec.desktop ] || fail recovery-desktop-present-before-load
[ ! -e "$private_perl" ] || fail private-perl-present-before-load

stage module-load
module_load_start=$(/usr/bin/awk '{ print $1 }' /proc/uptime)
if ! zxmod load "$module_path"; then
    fail module-load
fi
module_load_end=$(/usr/bin/awk '{ print $1 }' /proc/uptime)
module_load_ms=$(/usr/bin/awk -v start="$module_load_start" -v finish="$module_load_end" \
    'BEGIN { printf "%.0f", (finish - start) * 1000 }')
printf 'EFILINUX_RECOVERY_MODULE_LOAD_MS=%s\n' "$module_load_ms"
stage module-loaded
/usr/bin/awk -F '\t' '$1 == "recovery" { found=1 } END { exit !found }' /run/zxmod/active || fail module-active-record

stage efi-variables
[ -d /sys/firmware/efi ] || fail efi-runtime-missing
mountpoint -q /sys/firmware/efi/efivars || fail efivarfs-not-mounted
/usr/bin/efibootmgr -v > /run/efibootmgr.log 2>&1 || {
    cat /run/efibootmgr.log
    fail efi-variables-unreadable
}

stage presence-checks
for command in \
    clonezilla ocs-sr testdisk fsarchiver partclone.info fls wimlib-imagex \
    ldmtool dislocker sshfs chntpw qemu-img qemu-nbd nbd-client mount.nfs \
    cifs.upcall wget lvm dialog jq bc nc.traditional bzip2 lz4 lzop pigz \
    pbzip2 lzip plzip sha512sum glxinfo; do
    [ -x "/usr/bin/$command" ] || fail "command-missing:$command"
done
for command in \
    qphotorec efibooteditor gsmartcontrol hardinfo2 gtkhash gigolo kdiskmark \
    fio usbimager btop mc ncdu nwipe grsync nmtui recovery-gui-root \
    recovery-kdiskmark-session; do
    [ -x "/opt/recovery/bin/$command" ] || fail "private-command-missing:$command"
done
[ -x /opt/recovery/libexec/recovery-privileged-launch ] ||
    fail privileged-helper-missing
[ -f /usr/share/polkit-1/actions/org.efilinux.recovery.policy ] ||
    fail recovery-polkit-policy-missing
for desktop in \
    recovery-qphotorec.desktop recovery-efibooteditor.desktop \
    recovery-gsmartcontrol.desktop hardinfo2.desktop \
    org.gtkhash.gtkhash.desktop gigolo.desktop kdiskmark.desktop \
    usbimager.desktop btop.desktop grsync.desktop recovery-mc.desktop \
    recovery-ncdu.desktop recovery-nwipe.desktop recovery-nmtui.desktop; do
    [ -f "/usr/share/applications/$desktop" ] || fail "desktop-missing:$desktop"
done
[ -x "$private_perl" ] || fail private-perl-missing
[ ! -e /usr/bin/perl ] || fail global-perl-leaked

stage perl-modules
"$private_perl" \
    -MData::Dumper \
    -MDigest::SHA \
    -MEncode \
    -MIO::Socket \
    -MJSON::PP \
    -MPOSIX \
    -MSocket \
    -e 'print qq(EFILINUX_RECOVERY_PERL_OK\n)' |
    /usr/bin/grep -Fxq EFILINUX_RECOVERY_PERL_OK || fail private-perl-modules

stage clonezilla-functions
DRBL_SCRIPT_PATH=/opt/recovery/share/drbl \
DRBL_CONFIG_DIR=/opt/recovery/etc/drbl \
/usr/bin/bash -c '
    set +e
    . "$DRBL_SCRIPT_PATH/sbin/drbl-conf-functions"
    conf_status=$?
    . "$DRBL_SCRIPT_PATH/sbin/ocs-functions"
    ocs_status=$?
    test "$conf_status" -eq 0
    test "$ocs_status" -eq 0
    test "$(command -v perl)" = /opt/recovery/perl/bin/perl
    type check_if_root >/dev/null
    type USAGE_common_save >/dev/null
' || fail clonezilla-function-chain

stage command-probes
expect_output 'Version: 7.2' /usr/bin/testdisk /version
expect_output 'fsarchiver 0.8.9' /usr/bin/fsarchiver --version
expect_output 'Partclone : v0.3.47' /usr/bin/partclone.info -v
expect_output 'The Sleuth Kit ver 4.15.0' /usr/bin/fls -V
expect_output 'wimlib-imagex 1.14.5' /usr/bin/wimlib-imagex --version
expect_output 'qemu-img version 11.0.3' /usr/bin/qemu-img --version
expect_output 'This is nbd-client, from nbd 3.24' /usr/bin/nbd-client --version
expect_output 'version: 7.7' /usr/bin/cifs.upcall --version
expect_output 'GNU Wget 1.25.0' /usr/bin/wget --version
expect_output 'LVM version:     2.03.41' /usr/bin/lvm version
expect_output 'jq-1.8.2' /usr/bin/jq --version
expect_output 'bc 1.08.2' /usr/bin/bc --version
expect_output 'Usage: glxinfo' /usr/bin/glxinfo -h

stage compression
compression_source=/run/efilinux-compression-source
compression_output=/run/efilinux-compression-output
printf '%s\n' \
    'EFI Linux compression compatibility' \
    'spaces ; dollars $ and unicode 恢复' > "$compression_source"
compression_roundtrip() {
    compressor=$1
    decompressor=$2
    archive=$3
    shift 3
    "/usr/bin/$compressor" "$@" "$compression_source" > "$archive" ||
        fail "compression-create:$compressor"
    "/usr/bin/$decompressor" -dc "$archive" > "$compression_output" ||
        fail "compression-read:$decompressor"
    cmp "$compression_source" "$compression_output" ||
        fail "compression-compare:$compressor"
}
compression_roundtrip bzip2 bzip2 /run/source.bz2 -c
compression_roundtrip pigz pigz /run/source.gz -c
compression_roundtrip pbzip2 pbzip2 /run/source.pbz2 -c
compression_roundtrip lzip lzip /run/source.lz -c
compression_roundtrip plzip plzip /run/source.plz -c
compression_roundtrip lzop lzop /run/source.lzo -c
/usr/bin/lz4 -q -c "$compression_source" > /run/source.lz4 || fail compression-create:lz4
/usr/bin/lz4 -q -d -c /run/source.lz4 > "$compression_output" || fail compression-read:lz4
cmp "$compression_source" "$compression_output" || fail compression-compare:lz4

stage grsync-preview
preview_source='/run/grsync source;literal'
preview_destination='/run/grsync destination dollar$'
mkdir -p "$preview_source" "$preview_destination"
preview_output=$(/opt/recovery/bin/grsync --preview "$preview_source" "$preview_destination") ||
    fail grsync-preview
set +e
eval "set -- $preview_output"
preview_parse_status=$?
set -e
[ "$preview_parse_status" -eq 0 ] || fail grsync-preview-quoting
[ "$#" -eq 8 ] || fail grsync-preview-count
[ "$1" = rsync ] || fail grsync-preview-command
[ "$2" = --archive ] || fail grsync-preview-archive
[ "$3" = --human-readable ] || fail grsync-preview-readable
[ "$4" = --info=progress2 ] || fail grsync-preview-progress
[ "$5" = --partial ] || fail grsync-preview-partial
[ "$6" = --dry-run ] || fail grsync-preview-dry-run
[ "$7" = "$preview_source/" ] || fail grsync-preview-source
[ "$8" = "$preview_destination" ] || fail grsync-preview-destination

stage clonezilla-prepare
clonezilla_source_image=/run/clonezilla-source.img
clonezilla_target_image=/run/clonezilla-target.img
clonezilla_repository=/run/clonezilla-images
clonezilla_source_mount=/run/clonezilla-source-mount
clonezilla_target_mount=/run/clonezilla-target-mount
clonezilla_reference=/run/clonezilla-reference
truncate -s 64M "$clonezilla_source_image" "$clonezilla_target_image"
printf 'label: dos\n,48M,L,*\n' | /usr/bin/sfdisk "$clonezilla_source_image" >/dev/null ||
    fail clonezilla-source-partition-table
printf 'label: dos\n,48M,L,*\n' | /usr/bin/sfdisk "$clonezilla_target_image" >/dev/null ||
    fail clonezilla-target-partition-table
clonezilla_source_loop=$(/usr/bin/losetup --find --show --partscan "$clonezilla_source_image") ||
    fail clonezilla-source-loop
clonezilla_target_loop=$(/usr/bin/losetup --find --show --partscan "$clonezilla_target_image") ||
    fail clonezilla-target-loop
clonezilla_source_part="${clonezilla_source_loop}p1"
clonezilla_target_part="${clonezilla_target_loop}p1"
clonezilla_wait=0
while [ ! -b "$clonezilla_source_part" ] || [ ! -b "$clonezilla_target_part" ]; do
    [ "$clonezilla_wait" -lt 10 ] || fail clonezilla-loop-partitions
    sleep 1
    clonezilla_wait=$((clonezilla_wait + 1))
done
/usr/bin/mkfs.ext4 -q -F "$clonezilla_source_part" || fail clonezilla-source-filesystem
mkdir -p \
    "$clonezilla_repository" \
    "$clonezilla_source_mount" \
    "$clonezilla_target_mount" \
    "$clonezilla_reference"
mount "$clonezilla_source_part" "$clonezilla_source_mount" || fail clonezilla-source-mount
mkdir -p "$clonezilla_source_mount/documents/subdirectory"
printf '%s\n' 'EFI Linux Clonezilla local recovery' \
    > "$clonezilla_source_mount/documents/readme.txt"
printf '%s\n' 'spaces ; dollars $ and unicode 恢复' \
    > "$clonezilla_source_mount/documents/subdirectory/special name.txt"
ln -s 'subdirectory/special name.txt' "$clonezilla_source_mount/documents/link"
cp -a "$clonezilla_source_mount/documents" "$clonezilla_reference/"
sync
umount "$clonezilla_source_mount" || fail clonezilla-source-unmount

clonezilla_environment() {
    PATH=/opt/recovery/perl/bin:/opt/recovery/bin:/usr/bin:/bin \
    DRBL_SCRIPT_PATH=/opt/recovery/share/drbl \
    DRBL_CONFIG_DIR=/opt/recovery/etc/drbl \
    "$@"
}
clonezilla_source_name=${clonezilla_source_part#/dev/}
clonezilla_target_name=${clonezilla_target_part#/dev/}
mkdir -p /var/log/clonezilla
stage clonezilla-save
clonezilla_environment /usr/bin/timeout --kill-after=10 120 /usr/bin/ocs-sr \
    --ocsroot "$clonezilla_repository" \
    --batch --nogui \
    -q2 -c -j2 -z1p -i 2000 -sfsck -senc -p true \
    saveparts local-roundtrip "$clonezilla_source_name" \
    > /mnt/clonezilla-save.log 2>&1 || {
        cat /mnt/clonezilla-save.log
        fail clonezilla-saveparts
    }
stage clonezilla-restore
clonezilla_environment /usr/bin/timeout --kill-after=10 120 /usr/bin/ocs-sr \
    --ocsroot "$clonezilla_repository" \
    --batch --nogui \
    -g auto -e1 auto -e2 -y -r --no-fdisk --no-restore-mbr -p true \
    restoreparts local-roundtrip "$clonezilla_target_name" \
    > /mnt/clonezilla-restore.log 2>&1 || {
        cat /mnt/clonezilla-restore.log
        fail clonezilla-restoreparts
    }
stage clonezilla-verify
mount -o ro "$clonezilla_target_part" "$clonezilla_target_mount" ||
    fail clonezilla-target-mount
[ -d "$clonezilla_target_mount/documents/subdirectory" ] ||
    fail clonezilla-restored-directory
cmp "$clonezilla_reference/documents/readme.txt" \
    "$clonezilla_target_mount/documents/readme.txt" ||
    fail clonezilla-restored-readme
cmp "$clonezilla_reference/documents/subdirectory/special name.txt" \
    "$clonezilla_target_mount/documents/subdirectory/special name.txt" ||
    fail clonezilla-restored-special-file
[ -L "$clonezilla_target_mount/documents/link" ] ||
    fail clonezilla-restored-symlink
[ "$(readlink "$clonezilla_target_mount/documents/link")" = \
    'subdirectory/special name.txt' ] || fail clonezilla-restored-symlink-target
umount "$clonezilla_target_mount" || fail clonezilla-target-unmount
/usr/bin/losetup --detach "$clonezilla_source_loop" || fail clonezilla-source-detach
/usr/bin/losetup --detach "$clonezilla_target_loop" || fail clonezilla-target-detach
rm -rf \
    "$clonezilla_source_image" \
    "$clonezilla_target_image" \
    "$clonezilla_repository" \
    "$clonezilla_source_mount" \
    "$clonezilla_target_mount" \
    "$clonezilla_reference"

stage clonezilla-network-block
set +e
PATH=/opt/recovery/perl/bin:/opt/recovery/bin:/usr/bin:/bin \
DRBL_SCRIPT_PATH=/opt/recovery/share/drbl \
DRBL_CONFIG_DIR=/opt/recovery/etc/drbl \
    /usr/bin/ocs-sr -b multicast_restoredisk blocked-image sda 2232 \
    > /run/clonezilla-network-mode.log 2>&1
clonezilla_network_status=$?
set -e
[ "$clonezilla_network_status" -eq 2 ] || {
    cat /run/clonezilla-network-mode.log
    fail clonezilla-network-mode-status
}
grep -Fq 'network deployment modes are not available' /run/clonezilla-network-mode.log ||
    fail clonezilla-network-mode-message

stage fio
fio_file=/run/efilinux-fio-read-test
/usr/bin/dd if=/dev/zero of="$fio_file" bs=1M count=2 status=none || fail fio-source
/opt/recovery/bin/fio \
    --name=recovery-read-smoke \
    --filename="$fio_file" \
    --rw=read \
    --bs=4k \
    --size=2M \
    --ioengine=sync \
    --direct=0 \
    --output=/run/fio-read-smoke.log || {
        cat /run/fio-read-smoke.log 2>/dev/null || true
        fail fio-read-smoke
    }
rm -f "$fio_file"

stage qphotorec
qt_runtime=/run/efilinux-qt-runtime
mkdir -p "$qt_runtime"
chmod 0700 "$qt_runtime"
set +e
HOME=/run \
XDG_RUNTIME_DIR="$qt_runtime" \
QT_QPA_PLATFORM=offscreen \
QT_PLUGIN_PATH=/opt/recovery/lib/qt6/plugins \
    timeout 3 /opt/recovery/libexec/recovery-privileged-launch qphotorec \
    > /run/qphotorec.log 2>&1
qphotorec_status=$?
set -e
[ "$qphotorec_status" -eq 124 ] || {
    cat /run/qphotorec.log
    fail qphotorec-offscreen
}

stage efibooteditor
set +e
HOME=/run \
XDG_RUNTIME_DIR="$qt_runtime" \
QT_QPA_PLATFORM=offscreen \
QT_PLUGIN_PATH=/opt/recovery/lib/qt6/plugins \
    timeout 3 /opt/recovery/libexec/recovery-privileged-launch efibooteditor \
    > /run/efibooteditor.log 2>&1
efibooteditor_status=$?
set -e
[ "$efibooteditor_status" -eq 124 ] || {
    cat /run/efibooteditor.log
    fail efibooteditor-offscreen
}

stage kdiskmark
set +e
HOME=/run \
XDG_RUNTIME_DIR="$qt_runtime" \
DISPLAY=:99 \
QT_QPA_PLATFORM=offscreen \
QT_PLUGIN_PATH=/opt/recovery/lib/qt6/plugins \
    timeout 8 /opt/recovery/libexec/recovery-privileged-launch kdiskmark \
    > /run/kdiskmark.log 2>&1
kdiskmark_status=$?
set -e
[ "$kdiskmark_status" -eq 124 ] || {
    cat /run/kdiskmark.log
    fail kdiskmark-offscreen
}

stage nmtui
/opt/recovery/bin/nmtui --help > /run/nmtui.log 2>&1 || {
    cat /run/nmtui.log
    fail nmtui-help
}

stage gtkhash-runtime
mkdir -p /run/user/1000
chown user:user /run/user/1000
chmod 0700 /run/user/1000
set +e
/usr/bin/su -s /usr/bin/sh user -c \
    'XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:99 /opt/recovery/bin/gtkhash --help' \
    > /run/gtkhash.log 2>&1
gtkhash_status=$?
set -e
[ -d /run/user/1000/efilinux-recovery ] || {
    cat /run/gtkhash.log
    fail gtkhash-user-runtime
}
if [ "$gtkhash_status" -ne 0 ] && /usr/bin/grep -q 'Permission denied' /run/gtkhash.log; then
    cat /run/gtkhash.log
    fail gtkhash-permission
fi

stage kernel-modules
for module in nbd cifs nfs fuse; do
    modprobe "$module" || fail "kernel-module:$module"
    [ -d "/sys/module/$module" ] || fail "kernel-module-state:$module"
done
udevadm settle --timeout=10 2>/dev/null || true
[ -b /dev/nbd0 ] || fail nbd-device-missing

stage qemu-nbd
image=/run/efilinux-recovery-test.qcow2
/usr/bin/qemu-img create -q -f qcow2 "$image" 16M || fail qemu-img-create
/usr/bin/qemu-nbd --connect=/dev/nbd0 --format=qcow2 "$image" || fail qemu-nbd-connect
nbd_size=
nbd_wait=0
while [ "$nbd_wait" -lt 10 ]; do
    nbd_size=$(/usr/bin/blockdev --getsize64 /dev/nbd0 2>/dev/null || true)
    [ "$nbd_size" = 16777216 ] && break
    sleep 1
    nbd_wait=$((nbd_wait + 1))
done
[ "$nbd_size" = 16777216 ] || fail qemu-nbd-size
/usr/bin/qemu-nbd --disconnect /dev/nbd0 || fail qemu-nbd-disconnect
rm -f "$image"

recovery_processes() {
    recovery_process_found=1
    for recovery_proc in /proc/[0-9]*; do
        [ -r "$recovery_proc/maps" ] || continue
        if /usr/bin/grep -q '/opt/recovery/' "$recovery_proc/maps" 2>/dev/null; then
            recovery_process_found=0
            if [ "${1:-}" = print ]; then
                recovery_pid=${recovery_proc##*/}
                recovery_name=$(cat "$recovery_proc/comm" 2>/dev/null || printf unknown)
                recovery_exe=$(readlink "$recovery_proc/exe" 2>/dev/null || printf unknown)
                printf 'recovery process still active: pid=%s name=%s exe=%s\n' \
                    "$recovery_pid" "$recovery_name" "$recovery_exe" >&2
            fi
        fi
    done
    return "$recovery_process_found"
}

stage process-cleanup
recovery_process_wait=0
while recovery_processes && [ "$recovery_process_wait" -lt 15 ]; do
    sleep 1
    recovery_process_wait=$((recovery_process_wait + 1))
done
if recovery_processes; then
    recovery_processes print || true
    fail recovery-process-remains
fi

stage module-unload
touch /opt/recovery/must-not-write 2>/dev/null &&
    fail module-view-writable
zxmod unload recovery || fail module-unload
[ ! -e /run/zxmod/loops/recovery ] || fail module-loop-record-remains
/usr/bin/awk -F '\t' '$1 == "recovery" { found=1 } END { exit found }' \
    /run/zxmod/active || fail module-active-record-remains
[ ! -e /usr/bin/clonezilla ] || fail clonezilla-remains-after-unload
[ ! -e /opt/recovery/bin/qphotorec ] || fail qphotorec-remains-after-unload
[ ! -e /opt/recovery/bin/nmtui ] || fail nmtui-remains-after-unload
[ ! -e /usr/share/applications/recovery-qphotorec.desktop ] || fail recovery-desktop-remains-after-unload
[ ! -e "$private_perl" ] || fail private-perl-remains-after-unload
wait_for_module_loop_release

final_mount_count=$(module_mount_count)
[ "$final_mount_count" = 4 ] || fail module-runtime-mount-count
[ -z "$(/usr/bin/find /run/zxmod/retired -mindepth 1 -print -quit)" ] ||
    fail retired-generation-remains
[ "$(/usr/bin/find /run/zxmod/generations -mindepth 1 -maxdepth 1 -type d |
    /usr/bin/wc -l)" = 1 ] || fail generation-directory-count

stage complete
printf 'EFILINUX_RECOVERY_MOUNT_COUNT=%s\n' "$final_mount_count"
printf 'EFILINUX_RECOVERY_OK\n'
poweroff -f
