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

module_loop_is_present() {
    /usr/bin/losetup --associated "$module_path" 2>/dev/null |
        /usr/bin/grep -q .
}

wait_for_module_loop_release() {
    recovery_wait=0
    while module_loop_is_present; do
        [ "$recovery_wait" -lt 10 ] || fail module-loop-leaked
        sleep 1
        recovery_wait=$((recovery_wait + 1))
    done
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

[ "$(id -u)" = 0 ] || fail not-root
[ -f "$module_path" ] || fail module-missing
[ ! -e /usr/bin/clonezilla ] || fail clonezilla-present-before-load
[ ! -e "$private_perl" ] || fail private-perl-present-before-load

initial_mount_count=$(module_mount_count)
if ! zxmod load "$module_path"; then
    fail module-load
fi
/usr/bin/awk -F '\t' '$1 == "recovery" { found=1 } END { exit !found }' /run/zxmod/active || fail module-active-record

for command in \
    clonezilla ocs-sr testdisk fsarchiver partclone.info fls wimlib-imagex \
    ldmtool dislocker sshfs chntpw qemu-img qemu-nbd nbd-client mount.nfs \
    cifs.upcall wget lvm dialog jq bc nc.traditional; do
    [ -x "/usr/bin/$command" ] || fail "command-missing:$command"
done
[ -x "$private_perl" ] || fail private-perl-missing
[ ! -e /usr/bin/perl ] || fail global-perl-leaked

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

for module in nbd cifs nfs fuse; do
    modprobe "$module" || fail "kernel-module:$module"
    [ -d "/sys/module/$module" ] || fail "kernel-module-state:$module"
done
udevadm settle --timeout=10 2>/dev/null || true
[ -b /dev/nbd0 ] || fail nbd-device-missing

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

touch /opt/recovery/must-not-write 2>/dev/null &&
    fail module-view-writable
exec 3</opt/recovery/packages.tsv || fail held-fd-open
zxmod unload recovery || fail module-unload
[ ! -e /usr/bin/clonezilla ] || fail clonezilla-remains-after-unload
[ ! -e "$private_perl" ] || fail private-perl-remains-after-unload
IFS= read -r held_header <&3 || fail held-fd-read
[ "$held_header" = "$(printf 'package\tversion')" ] || fail held-fd-content
exec 3<&-
wait_for_module_loop_release

final_mount_count=$(module_mount_count)
[ "$final_mount_count" = "$initial_mount_count" ] || fail mount-count-grew

printf 'EFILINUX_RECOVERY_MOUNT_COUNT=%s\n' "$final_mount_count"
printf 'EFILINUX_RECOVERY_OK\n'
poweroff -f
