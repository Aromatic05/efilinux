#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"

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

[[ -L "$rootfs/init" && $(readlink -- "$rootfs/init") == /usr/bin/init ]] || \
    die "final /init does not select SysVinit"

for file in \
    /etc/inittab /etc/rc.d/rcS /etc/rc.d/rc /etc/rc.d/rc.shutdown \
    /etc/sysconfig/hostname /etc/sysconfig/network /etc/sysconfig/clock \
    /etc/syslog.conf /etc/crontab /etc/dbus-1/system.conf \
    /etc/dhcpcd.conf /etc/ssh/sshd_config \
    /etc/pam.d/system-auth /etc/pam.d/login /etc/pam.d/sshd \
    /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    require_file "$file"
done

for directory in \
    /etc/rc.d/init.d /etc/rc.d/rc3.d /etc/rc.d/rc6.d \
    /etc/ssh /root/.ssh /var/empty /var/lib/dbus /var/log /var/spool/cron; do
    require_directory "$directory"
done

for service in mountvirtfs udev localnet setclock syslog dbus cron dhcpcd sshd; do
    require_service "$service"
done

require_program init sysvinit
require_program telinit sysvinit
require_program shutdown sysvinit
require_program udevadm udev
require_program '[' busybox
require_program hwclock "util-linux-$UTIL_LINUX_VERSION"
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
require_program dhcpcd dhcpcd
require_program ssh openssh
require_program sshd openssh
require_program ssh-keygen openssh

for helper in ata_id cdrom_id dmi_memory_id fido_id iocost mtd_probe scsi_id v4l_id; do
    [[ -x "$rootfs/usr/lib/udev/$helper" ]] || die "Udev helper is missing: $helper"
done
[[ -x "$rootfs/usr/lib/ssh/sftp-server" ]] || die "OpenSSH SFTP server is missing"

[[ $(stat -c '%a' "$rootfs/etc/shadow") == 600 ]] || die "/etc/shadow permissions are not 0600"
[[ $(stat -c '%a' "$rootfs/etc/gshadow") == 600 ]] || die "/etc/gshadow permissions are not 0600"
[[ $(stat -c '%a' "$rootfs/root/.ssh") == 700 ]] || die "/root/.ssh permissions are not 0700"
for privileged_file in \
    /usr/bin/passwd /usr/bin/su /usr/bin/newgrp /usr/bin/crontab \
    /usr/libexec/dbus-daemon-launch-helper; do
    [[ $(stat -c '%a' "$rootfs$privileged_file") == 4755 ]] || \
        die "$privileged_file permissions are not 4755"
done

[[ -L "$rootfs/var/run" && $(readlink -- "$rootfs/var/run") == /run ]] || \
    die "/var/run does not point to /run"
[[ -L "$rootfs/etc/rc.d/rc3.d/S60sshd" ]] || die "runlevel 3 does not start sshd"
[[ -L "$rootfs/etc/rc.d/rc6.d/K10sshd" ]] || die "runlevel 6 does not stop sshd"

root_account=$(awk -F: '$3 == 0 { print $1; exit }' "$rootfs/etc/passwd")
root_password_hash=$(awk -F: -v account="$root_account" \
    '$1 == account { print $2; exit }' "$rootfs/etc/shadow")
expected_root_password_hash=$(openssl passwd -6 -salt "$root_account" "$root_account")
[[ "$root_password_hash" == "$expected_root_password_hash" ]] || \
    die "root password does not match the root account name"
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
[[ ! -e "$rootfs/usr/bin/systemd" && ! -d "$rootfs/usr/lib/systemd" ]] || \
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
"$loader" --library-path "$library_path" "$rootfs/usr/bin/ssh" -V >/dev/null 2>&1

log "002-system structure, ownership, permissions, and target programs passed"
