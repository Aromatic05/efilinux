#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"

[[ -f "$EFILINUX_ROOTFS_OWNERS" ]] || die "rootfs ownership manifest is missing"
[[ -f "$EFILINUX_ROOTFS_FAKEROOT_STATE" ]] || die "rootfs fakeroot metadata is missing"

rootfs_owner() {
    local path=$1
    awk -F '\t' -v path="$path" \
        'NR > 1 && $1 == path && $2 != "directory" { print $3; exit }' \
        "$EFILINUX_ROOTFS_OWNERS"
}

rootfs_stat() {
    fakeroot -i "$EFILINUX_ROOTFS_FAKEROOT_STATE" -- \
        stat -c "$1" "$rootfs$2"
}

require_file() {
    local path=$1
    [[ -f "$rootfs$path" ]] || die "system file is missing: $path"
}

require_directory() {
    local path=$1
    [[ -d "$rootfs$path" ]] || die "system directory is missing: $path"
}

require_program() {
    local name=$1
    local owner=$2
    local path="$rootfs/usr/bin/$name"
    [[ -x "$path" ]] || die "system program is missing: $name"
    [[ $(rootfs_owner "/usr/bin/$name") == "$owner" ]] || die "$name is not owned by $owner"
}

require_service() {
    local name=$1
    local path="$rootfs/etc/rc.d/init.d/$name"
    [[ -x "$path" ]] || die "service script is missing: $name"
}

[[ -f "$rootfs/init" && -x "$rootfs/init" ]] || \
    die "final /init is not an executable system-init wrapper"
[[ $(rootfs_owner /init) == system-init ]] || die "/init is not owned by system-init"
grep -Fq '/usr/bin/fsmeta-replay' "$rootfs/init" || \
    die "/init does not replay ACL and capability metadata"
grep -Fq 'exec /usr/bin/init "$@"' "$rootfs/init" || \
    die "/init does not enter SysVinit after metadata replay"

for file in \
    /etc/inittab /etc/rc.d/rcS /etc/rc.d/rc /etc/rc.d/rc.shutdown \
    /etc/sysconfig/hostname /etc/sysconfig/network /etc/sysconfig/clock \
    /etc/syslog.conf /etc/crontab /etc/dbus-1/system.conf \
    /etc/dhcpcd.conf /etc/ssh/sshd_config /etc/doas.conf /etc/ssl/openssl.cnf \
    /etc/pam.d/system-auth /etc/pam.d/login /etc/pam.d/sshd /etc/pam.d/doas \
    /etc/passwd /etc/group /etc/shadow /etc/gshadow \
    /etc/filemeta/ownership.tsv /etc/filemeta/caps/iputils; do
    require_file "$file"
done

for directory in \
    /etc/rc.d/init.d /etc/rc.d/rc3.d /etc/rc.d/rc6.d \
    /etc/ssh /root/.ssh /home/user /var/empty /var/lib/dbus /var/log /var/spool/cron; do
    require_directory "$directory"
done

for service in mountvirtfs udev localnet setclock syslog dbus cron dhcpcd sshd; do
    require_service "$service"
done

require_program init sysvinit
require_program fsmeta-replay fsmeta-replay
require_program telinit sysvinit
require_program shutdown sysvinit
require_program udevadm udev
require_program '[' coreutils
require_program hwclock util-linux
require_program login shadow
require_program passwd shadow
require_program useradd shadow
require_program syslogd sysklogd
require_program crond cronie
require_program crontab cronie
require_program dbus-daemon dbus
require_program dbus-uuidgen dbus
require_program ip iproute2
require_program ss iproute2
require_program ping iputils
require_program arping iputils
require_program tracepath iputils
require_program dhcpcd dhcpcd
require_program ssh openssh
require_program sshd openssh
require_program ssh-keygen openssh
require_program doas doas
require_program openssl openssl

for helper in ata_id cdrom_id dmi_memory_id fido_id iocost mtd_probe scsi_id v4l_id; do
    [[ -x "$rootfs/usr/lib/udev/$helper" ]] || die "Udev helper is missing: $helper"
done
[[ -x "$rootfs/usr/lib/ssh/sftp-server" ]] || die "OpenSSH SFTP server is missing"
OPENSSL_CONF="$rootfs/etc/ssl/openssl.cnf" \
    "$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/openssl" list -providers > "$EFILINUX_TEST/openssl-providers.txt"
grep -Fq 'default' "$EFILINUX_TEST/openssl-providers.txt" || \
    die "OpenSSL default provider did not load with the packaged configuration"
if grep -Fq 'legacy' "$EFILINUX_TEST/openssl-providers.txt"; then
    die "OpenSSL legacy provider is enabled globally"
fi

[[ $(rootfs_stat '%a' /etc/shadow) == 600 ]] || die "/etc/shadow permissions are not 0600"
[[ $(rootfs_stat '%a' /etc/gshadow) == 600 ]] || die "/etc/gshadow permissions are not 0600"
for public_config in \
    /etc/passwd /etc/group /etc/nsswitch.conf /etc/hosts \
    /etc/pam.d/system-auth /etc/pam.d/login /etc/profile; do
    [[ $(rootfs_stat '%a' "$public_config") == 644 ]] || \
        die "$public_config permissions are not 0644"
done
[[ $(rootfs_stat '%a' /root/.ssh) == 700 ]] || die "/root/.ssh permissions are not 0700"
for privileged_file in \
    /usr/bin/passwd /usr/bin/su /usr/bin/newgrp /usr/bin/crontab /usr/bin/doas \
    /usr/bin/pkexec /usr/lib/polkit-1/polkit-agent-helper-1 \
    /usr/libexec/dbus-daemon-launch-helper; do
    [[ $(rootfs_stat '%a' "$privileged_file") == 4755 ]] || \
        die "$privileged_file permissions are not 4755"
done

[[ -L "$rootfs/var/run" && $(readlink -- "$rootfs/var/run") == /run ]] || \
    die "/var/run does not point to /run"
[[ -L "$rootfs/etc/rc.d/rc3.d/S70sshd" ]] || die "runlevel 3 does not start sshd"
[[ -L "$rootfs/etc/rc.d/rc6.d/K10sshd" ]] || die "runlevel 6 does not stop sshd"

root_account=$(awk -F: '$3 == 0 { print $1; exit }' "$rootfs/etc/passwd")
root_password_hash=$(awk -F: -v account="$root_account" \
    '$1 == account { print $2; exit }' "$rootfs/etc/shadow")
expected_root_password_hash=$(openssl passwd -6 -salt "$root_account" "$root_account")
[[ "$root_password_hash" == "$expected_root_password_hash" ]] || \
    die "root password does not match the root account name"
user_passwd=$(awk -F: '$1 == "user" { print; exit }' "$rootfs/etc/passwd")
[[ "$user_passwd" == 'user:x:1000:1000:User:/home/user:/usr/bin/bash' ]] || \
    die "normal user account is missing or malformed"
user_password_hash=$(awk -F: '$1 == "user" { print $2; exit }' "$rootfs/etc/shadow")
expected_user_password_hash=$(openssl passwd -6 -salt user user)
[[ "$user_password_hash" == "$expected_user_password_hash" ]] || \
    die "user password does not match the user account name"
grep -Eq '^user:x:1000:$' "$rootfs/etc/group" || \
    die "user primary group is missing"
grep -Eq '^netdev:x:[0-9]+:([^:]*,)?user(,[^:]*)?$' "$rootfs/etc/group" || \
    die "netdev group is missing or does not include user"
grep -Eq '^wheel:x:10:([^:]*,)?user(,[^:]*)?$' "$rootfs/etc/group" || \
    die "user is not a member of wheel"
grep -Fxq 'permit persist :wheel' "$rootfs/etc/doas.conf" || \
    die "doas does not permit authenticated wheel elevation"
for pam_line in \
    'auth include system-auth' \
    'account include system-auth' \
    'session include system-auth'; do
    grep -Fxq "$pam_line" "$rootfs/etc/pam.d/doas" || \
        die "doas PAM service is missing: $pam_line"
done
grep -Eq '^wheel:\*::([^:]*,)?user(,[^:]*)?$' "$rootfs/etc/gshadow" || \
    die "user wheel membership is missing from gshadow"
[[ $(rootfs_stat '%u:%g:%a' /home/user) == '1000:1000:750' ]] || \
    die "/home/user ownership or permissions are incorrect"
grep -q '^sshd:' "$rootfs/etc/passwd" || die "sshd user is missing"
grep -q '^dbus:' "$rootfs/etc/passwd" || die "dbus user is missing"
grep -Eq '^PermitRootLogin[[:space:]]+prohibit-password$' "$rootfs/etc/ssh/sshd_config" || \
    die "sshd root-login policy is unsafe"
grep -Eq '^PasswordAuthentication[[:space:]]+no$' "$rootfs/etc/ssh/sshd_config" || \
    die "sshd password authentication is enabled"

if find "$rootfs/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -print -quit | grep -q .; then
    die "shared OpenSSH host keys were embedded in the rootfs"
fi
[[ ! -e "$rootfs/etc/machine-id" ]] || die "a shared machine ID was embedded in the rootfs"
[[ -L "$rootfs/var/lib/dbus/machine-id" && \
   $(readlink -- "$rootfs/var/lib/dbus/machine-id") == /etc/machine-id ]] || \
    die "D-Bus machine ID does not follow the runtime-generated machine ID"
[[ ! -e "$rootfs/usr/lib/udev/rules.d/99-systemd.rules" ]] || \
    die "systemd activation rules leaked into standalone Udev"
[[ ! -e "$rootfs/usr/bin/systemd" && ! -e "$rootfs/usr/lib/systemd/systemd" ]] || \
    die "systemd runtime artifacts leaked into the SysVinit rootfs"
grep -Fq 'PAGER=${PAGER:-cat}' "$rootfs/etc/profile" || \
    die "profile selects a pager that is not guaranteed to exist"
if grep -R -nE '(^|[[:space:];])\[[[:space:]]' "$rootfs/etc/rc.d" >/dev/null; then
    die "boot scripts use the unavailable [ command instead of test"
fi
grep -Fq 'start_daemon sshd /usr/bin/sshd ' "$rootfs/etc/rc.d/init.d/sshd" || \
    die "sshd is not started with an absolute executable path"

"$loader" --library-path "$library_path" "$rootfs/usr/bin/init" --version 2>&1 | grep -q 'init version'
"$loader" --library-path "$library_path" "$rootfs/usr/bin/udevadm" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/dbus-daemon" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/ip" -Version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/ping" -V >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/ssh" -V >/dev/null 2>&1
doas_decision=$(
    "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/doas" -C "$rootfs/etc/doas.conf" user /usr/bin/id
)
[[ $doas_decision == permit ]] || \
    die "doas does not permit wheel user elevation: $doas_decision"

for formal_network_tool in ip ss ping arping tracepath; do
    [[ ! -L "$rootfs/usr/bin/$formal_network_tool" ]] || \
        die "$formal_network_tool is still a BusyBox symbolic link"
done

log "002-system structure, ownership, permissions, and target programs passed"
