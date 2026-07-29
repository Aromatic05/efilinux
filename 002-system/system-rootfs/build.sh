#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk find openssl readelf sha256sum strip tar
ensure_directories

files_root="$ROOT/002-system/system-rootfs/files"
assembly="$EFILINUX_BUILD/assembly/system-rootfs"
reset_directory "$assembly"
package_materialization="$assembly/packages"
mkdir -p "$package_materialization"

stage() {
    local package=$1
    local directory="$package_materialization/$package"

    if [[ ! -d "$directory" ]]; then
        binary_package_materialize "$package" "$directory"
    fi
    printf '%s' "$directory"
}

sysv_stage=$(stage "sysvinit-$SYSVINIT_VERSION")
sysklogd_stage=$(stage "sysklogd-$SYSKLOGD_VERSION")
udev_stage=$(stage "systemd-$UDEV_SYSTEMD_VERSION")
libgudev_stage=$(stage "libgudev-$LIBGUDEV_VERSION")
pam_stage=$(stage "Linux-PAM-$LINUX_PAM_VERSION")
shadow_stage=$(stage "shadow-$SHADOW_VERSION")
openssl_stage=$(stage "openssl-$OPENSSL_VERSION")
expat_stage=$(stage "expat-$EXPAT_VERSION")
dbus_stage=$(stage "dbus-$DBUS_VERSION")
cronie_stage=$(stage "cronie-$CRONIE_VERSION")
iproute_stage=$(stage "iproute2-$IPROUTE2_VERSION")
iputils_stage=$(stage "iputils-$IPUTILS_VERSION")
dhcpcd_stage=$(stage "dhcpcd-$DHCPCD_VERSION")
openssh_stage=$(stage "openssh-$OPENSSH_VERSION")
util_linux_stage=$(stage "util-linux-$UTIL_LINUX_VERSION")

install_program_from() {
    local owner=$1
    local source=$2
    local name=${3:-$(basename -- "$source")}
    install_rootfs_program "$owner" "$source" "$name"
}

install_programs_from_directory() {
    local owner=$1
    local directory=$2
    shift 2
    local name

    for name in "$@"; do
        install_program_from "$owner" "$directory/$name" "$name"
    done
}

log "Replacing the runtime bootstrap with SysVinit"
ln -s /usr/bin/init "$assembly/init"
replace_rootfs_file sysvinit runtime-base "$assembly/init" /init

for base_config in passwd group nsswitch.conf hosts host.conf resolv.conf; do
    replace_rootfs_file \
        system-config runtime-base \
        "$files_root/etc/$base_config" "/etc/$base_config"
done

log "Installing system configuration"
while IFS= read -r -d '' source; do
    relative=${source#"$files_root"}
    case "$relative" in
        /etc/passwd|/etc/group|/etc/nsswitch.conf|/etc/hosts|/etc/host.conf|/etc/resolv.conf)
            continue
            ;;
    esac
    install_rootfs_file system-config "$source" "$relative"
done < <(find "$files_root" -type f -print0)

install_rootfs_file shadow "$shadow_stage/etc/login.defs" /etc/login.defs
install_rootfs_file openssh "$openssh_stage/etc/ssh/ssh_config" /etc/ssh/ssh_config
install_rootfs_file openssh "$openssh_stage/etc/ssh/moduli" /etc/ssh/moduli

root_account=$(awk -F: '$3 == 0 { print $1; exit }' "$EFILINUX_ROOTFS/etc/passwd")
root_password_hash=$(openssl passwd -6 -salt "$root_account" "$root_account")
awk -F: -v OFS=: -v account="$root_account" -v hash="$root_password_hash" \
    '$1 == account { $2 = hash } { print }' \
    "$EFILINUX_ROOTFS/etc/shadow" > "$assembly/shadow"
replace_rootfs_file \
    system-config system-config "$assembly/shadow" /etc/shadow

log "Installing SysVinit and console lifecycle tools"
install_programs_from_directory sysvinit "$sysv_stage/sbin" \
    init telinit shutdown runlevel halt reboot poweroff killall5 sulogin \
    bootlogd fstab-decode logsave
install_program_from sysvinit "$sysv_stage/bin/pidof" pidof
install_programs_from_directory sysvinit "$sysv_stage/usr/bin" \
    last lastb mesg readbootlog utmpdump wall
install_program_from util-linux "$util_linux_stage/usr/bin/agetty" agetty

log "Installing authentication and account management"
install_program_from openssl "$openssl_stage/usr/bin/openssl" openssl
install_programs_from_directory linux-pam "$pam_stage/usr/sbin" \
    faillock unix_chkpwd
install_programs_from_directory shadow "$shadow_stage/usr/bin" \
    chage chfn chsh expiry faillog gpasswd login newgrp passwd sg su
install_programs_from_directory shadow "$shadow_stage/usr/sbin" \
    chpasswd groupadd groupdel groupmod grpck grpconv grpunconv newusers \
    nologin pwck pwconv pwunconv useradd userdel usermod vigr vipw
install_rootfs_tree linux-pam "$pam_stage/usr/lib/security" /usr/lib/security

log "Installing device, logging, message bus, and scheduler services"
install_program_from sysklogd "$sysklogd_stage/usr/bin/syslogd" syslogd
install_program_from udev "$udev_stage/usr/bin/udevadm" udevadm
install_program_from udev "$udev_stage/usr/bin/udev-hwdb" udev-hwdb
install_program_from udev "$udev_stage/usr/sbin/udevd" udevd
install_rootfs_tree udev "$udev_stage/etc/udev" /etc/udev
install_rootfs_tree udev "$udev_stage/usr/lib/udev" /usr/lib/udev

install_programs_from_directory dbus "$dbus_stage/usr/bin" \
    dbus-daemon dbus-monitor dbus-run-session dbus-send dbus-uuidgen
install_rootfs_tree dbus "$dbus_stage/etc/dbus-1" /etc/dbus-1
install_rootfs_tree dbus "$dbus_stage/usr/share/dbus-1" /usr/share/dbus-1
install_rootfs_file dbus \
    "$dbus_stage/usr/libexec/dbus-daemon-launch-helper" \
    /usr/libexec/dbus-daemon-launch-helper

install_program_from cronie "$cronie_stage/usr/sbin/crond" crond
install_programs_from_directory cronie "$cronie_stage/usr/bin" crontab cronnext

log "Installing network and remote-maintenance tools"
install_programs_from_directory iproute2 "$iproute_stage/usr/bin" \
    ip ss bridge tc nstat rtmon
install_programs_from_directory iputils "$iputils_stage/usr/bin" \
    ping arping tracepath
install_program_from dhcpcd "$dhcpcd_stage/usr/bin/dhcpcd" dhcpcd
install_rootfs_tree dhcpcd "$dhcpcd_stage/usr/lib/dhcpcd" /usr/lib/dhcpcd
install_rootfs_tree dhcpcd "$dhcpcd_stage/usr/share/dhcpcd" /usr/share/dhcpcd

install_programs_from_directory openssh "$openssh_stage/usr/bin" \
    scp sftp ssh ssh-add ssh-agent ssh-keygen ssh-keyscan
install_program_from openssh "$openssh_stage/usr/sbin/sshd" sshd
install_rootfs_tree openssh "$openssh_stage/usr/lib/ssh" /usr/lib/ssh

log "Installing the system shared-library closure"
install_rootfs_library_family openssl "$openssl_stage" 'libcrypto.so.3*'
install_rootfs_library_family openssl "$openssl_stage" 'libssl.so.3*'
install_rootfs_library_family linux-pam "$pam_stage" 'libpam.so.0*'
install_rootfs_library_family linux-pam "$pam_stage" 'libpam_misc.so.0*'
install_rootfs_library_family expat "$expat_stage" 'libexpat.so.1*'
install_rootfs_library_family udev "$udev_stage" 'libudev.so.1*'
install_rootfs_library_family libgudev "$libgudev_stage" 'libgudev-1.0.so.0*'
install_rootfs_library_family dbus "$dbus_stage" 'libdbus-1.so.3*'

log "Creating runtime directories and runlevels"
mkdir -p \
    "$EFILINUX_ROOTFS/etc/cron.d" \
    "$EFILINUX_ROOTFS/root/.ssh" \
    "$EFILINUX_ROOTFS/var/empty" \
    "$EFILINUX_ROOTFS/var/lib/dbus" \
    "$EFILINUX_ROOTFS/var/lib/dhcpcd" \
    "$EFILINUX_ROOTFS/var/log" \
    "$EFILINUX_ROOTFS/var/spool/cron" \
    "$EFILINUX_ROOTFS/var/spool/mail" \
    "$EFILINUX_ROOTFS/usr/libexec"

for runlevel in 0 1 2 3 4 5 6; do
    mkdir -p "$EFILINUX_ROOTFS/etc/rc.d/rc${runlevel}.d"
done

for runlevel in 2 3 4 5; do
    install_rootfs_symlink system-config ../init.d/syslog "/etc/rc.d/rc${runlevel}.d/S20syslog"
    install_rootfs_symlink system-config ../init.d/dbus "/etc/rc.d/rc${runlevel}.d/S30dbus"
    install_rootfs_symlink system-config ../init.d/cron "/etc/rc.d/rc${runlevel}.d/S40cron"
    install_rootfs_symlink system-config ../init.d/dhcpcd "/etc/rc.d/rc${runlevel}.d/S50dhcpcd"
    install_rootfs_symlink system-config ../init.d/sshd "/etc/rc.d/rc${runlevel}.d/S60sshd"
done

for runlevel in 0 6; do
    install_rootfs_symlink system-config ../init.d/sshd "/etc/rc.d/rc${runlevel}.d/K10sshd"
    install_rootfs_symlink system-config ../init.d/dhcpcd "/etc/rc.d/rc${runlevel}.d/K20dhcpcd"
    install_rootfs_symlink system-config ../init.d/cron "/etc/rc.d/rc${runlevel}.d/K30cron"
    install_rootfs_symlink system-config ../init.d/dbus "/etc/rc.d/rc${runlevel}.d/K40dbus"
    install_rootfs_symlink system-config ../init.d/syslog "/etc/rc.d/rc${runlevel}.d/K50syslog"
done

install_rootfs_symlink system-config /run /var/run
install_rootfs_symlink system-config /run/lock /var/lock
install_rootfs_symlink system-config /etc/machine-id /var/lib/dbus/machine-id
install_rootfs_symlink system-config /proc/self/mounts /etc/mtab

chmod 0755 \
    "$EFILINUX_ROOTFS/etc/rc.d/rcS" \
    "$EFILINUX_ROOTFS/etc/rc.d/rc" \
    "$EFILINUX_ROOTFS/etc/rc.d/rc.shutdown" \
    "$EFILINUX_ROOTFS/etc/rc.d/init.d/"*
chmod 0600 "$EFILINUX_ROOTFS/etc/shadow" "$EFILINUX_ROOTFS/etc/gshadow"
chmod 0700 "$EFILINUX_ROOTFS/root/.ssh"
chmod 0755 "$EFILINUX_ROOTFS/var/empty"
touch \
    "$EFILINUX_ROOTFS/var/log/messages" \
    "$EFILINUX_ROOTFS/var/log/secure" \
    "$EFILINUX_ROOTFS/var/log/cron" \
    "$EFILINUX_ROOTFS/var/log/wtmp" \
    "$EFILINUX_ROOTFS/var/log/lastlog" \
    "$EFILINUX_ROOTFS/var/log/btmp"
chmod 0600 "$EFILINUX_ROOTFS/var/log/btmp"

strip_rootfs_elf
chmod 4755 \
    "$EFILINUX_ROOTFS/usr/bin/passwd" \
    "$EFILINUX_ROOTFS/usr/bin/su" \
    "$EFILINUX_ROOTFS/usr/bin/newgrp" \
    "$EFILINUX_ROOTFS/usr/bin/crontab" \
    "$EFILINUX_ROOTFS/usr/libexec/dbus-daemon-launch-helper"

if find "$EFILINUX_ROOTFS/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -print -quit | grep -q .; then
    die "OpenSSH host keys must not be embedded in the image"
fi

log "System rootfs assembly complete"
