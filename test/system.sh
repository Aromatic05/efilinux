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
    /etc/sysconfig/hostname /etc/sysconfig/network \
    /etc/syslog.conf /etc/crontab /etc/dbus-1/system.conf \
    /etc/dhcpcd.conf /etc/ssh/sshd_config \
    /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    require_file "$file"
done

for directory in \
    /etc/rc.d/init.d /etc/rc.d/rc3.d /etc/rc.d/rc6.d \
    /etc/ssh /root/.ssh /var/empty /var/lib/dbus /var/log /var/spool/cron; do
    require_directory "$directory"
done

for service in mountvirtfs udev localnet syslog dbus cron dhcpcd sshd; do
    require_service "$service"
done

require_program init sysvinit
require_program telinit sysvinit
require_program shutdown sysvinit
require_program udevadm udev
require_program login shadow
require_program passwd shadow
require_program useradd shadow
require_program syslogd sysklogd
require_program klogd sysklogd
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

[[ $(stat -c '%a' "$rootfs/etc/shadow") == 600 ]] || die "/etc/shadow permissions are not 0600"
[[ $(stat -c '%a' "$rootfs/etc/gshadow") == 600 ]] || die "/etc/gshadow permissions are not 0600"
[[ $(stat -c '%a' "$rootfs/root/.ssh") == 700 ]] || die "/root/.ssh permissions are not 0700"

grep -Eq '^root:[!*]:' "$rootfs/etc/shadow" || die "root password is not locked by default"
grep -q '^sshd:' "$rootfs/etc/passwd" || die "sshd user is missing"
grep -q '^dbus:' "$rootfs/etc/passwd" || die "dbus user is missing"
grep -Eq '^PermitRootLogin[[:space:]]+prohibit-password$' "$rootfs/etc/ssh/sshd_config" || \
    die "sshd root-login policy is unsafe"
grep -Eq '^PasswordAuthentication[[:space:]]+no$' "$rootfs/etc/ssh/sshd_config" || \
    die "sshd password authentication is enabled"

"$loader" --library-path "$library_path" "$rootfs/usr/bin/init" --version 2>&1 | grep -q 'init version'
"$loader" --library-path "$library_path" "$rootfs/usr/bin/udevadm" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/dbus-daemon" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/ip" -Version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/ssh" -V >/dev/null 2>&1

log "002-system structure, ownership, permissions, and target programs passed"
