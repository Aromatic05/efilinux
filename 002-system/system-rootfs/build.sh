#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/002-system/desktop-services/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk find glib-compile-schemas openssl readelf sha256sum strip tar
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
device_mapper_stage=$(stage "device-mapper-$LVM2_VERSION")
cryptsetup_stage=$(stage "cryptsetup-$CRYPTSETUP_VERSION")
libbytesize_stage=$(stage "libbytesize-$LIBBYTESIZE_VERSION")
libnvme_stage=$(stage "libnvme-$LIBNVME_VERSION")
mdadm_stage=$(stage "mdadm-$MDADM_VERSION")
elogind_stage=$(stage "elogind-$ELOGIND_VERSION")
polkit_stage=$(stage "polkit-$POLKIT_VERSION")
upower_stage=$(stage "upower-$UPOWER_VERSION")
libblockdev_stage=$(stage "libblockdev-$LIBBLOCKDEV_VERSION")
udisks_stage=$(stage "udisks-$UDISKS_VERSION")
gvfs_stage=$(stage "gvfs-$GVFS_VERSION")
iwd_stage=$(stage "iwd-$IWD_VERSION")
networkmanager_stage=$(stage "NetworkManager-$NETWORKMANAGER_VERSION")
pulseaudio_stage=$(stage "pulseaudio-$PULSEAUDIO_VERSION")
pipewire_stage=$(stage "pipewire-$PIPEWIRE_VERSION")
wireplumber_stage=$(stage "wireplumber-$WIREPLUMBER_VERSION")

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

install_tree_if_present() {
    local owner=$1
    local source=$2
    local destination=$3

    if [[ -d "$source" ]]; then
        install_rootfs_tree "$owner" "$source" "$destination"
    fi
}

install_library_families() {
    local owner=$1
    local staging=$2
    shift 2
    local pattern

    for pattern in "$@"; do
        install_rootfs_library_family "$owner" "$staging" "$pattern"
    done
}

log "Replacing the runtime bootstrap with SysVinit"
ln -s /usr/bin/init "$assembly/init"
replace_rootfs_file sysvinit runtime-base "$assembly/init" /init

for base_config in passwd group nsswitch.conf hosts host.conf resolv.conf; do
    replace_rootfs_file_mode \
        system-config runtime-base \
        "$files_root/etc/$base_config" "/etc/$base_config" 0644
done

log "Installing system configuration"
while IFS= read -r -d '' source; do
    relative=${source#"$files_root"}
    case "$relative" in
        /etc/passwd|/etc/group|/etc/nsswitch.conf|/etc/hosts|/etc/host.conf|/etc/resolv.conf)
            continue
            ;;
    esac
    install_rootfs_overlay_file system-config "$source" "$relative"
done < <(find "$files_root" -type f -print0)

install_rootfs_file shadow "$shadow_stage/etc/login.defs" /etc/login.defs
install_rootfs_file openssh "$openssh_stage/etc/ssh/ssh_config" /etc/ssh/ssh_config
install_rootfs_file openssh "$openssh_stage/etc/ssh/moduli" /etc/ssh/moduli

cp "$EFILINUX_ROOTFS/etc/shadow" "$assembly/shadow"
for account in root user; do
    password_hash=$(openssl passwd -6 -salt "$account" "$account")
    awk -F: -v OFS=: -v account="$account" -v hash="$password_hash" \
        '$1 == account { $2 = hash } { print }' \
        "$assembly/shadow" > "$assembly/shadow.next"
    mv "$assembly/shadow.next" "$assembly/shadow"
done
replace_rootfs_file_mode \
    system-config system-config "$assembly/shadow" /etc/shadow 0600

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

log "Installing login, authorization, and power services"
install_programs_from_directory "elogind-$ELOGIND_VERSION" "$elogind_stage/usr/bin" \
    loginctl elogind-inhibit
install_rootfs_file "elogind-$ELOGIND_VERSION" \
    "$elogind_stage/usr/libexec/elogind" /usr/libexec/elogind
install_rootfs_file "elogind-$ELOGIND_VERSION" \
    "$elogind_stage/usr/lib/security/pam_elogind.so" /usr/lib/security/pam_elogind.so
install_rootfs_tree "elogind-$ELOGIND_VERSION" \
    "$elogind_stage/usr/lib/elogind" /usr/lib/elogind

install_programs_from_directory "polkit-$POLKIT_VERSION" "$polkit_stage/usr/bin" \
    pkaction pkcheck pkexec pkttyagent
install_rootfs_tree "polkit-$POLKIT_VERSION" \
    "$polkit_stage/usr/lib/polkit-1" /usr/lib/polkit-1

install_program_from "upower-$UPOWER_VERSION" "$upower_stage/usr/bin/upower" upower
install_rootfs_file "upower-$UPOWER_VERSION" \
    "$upower_stage/usr/libexec/upowerd" /usr/libexec/upowerd

log "Installing storage and virtual filesystem services"
install_program_from "device-mapper-$LVM2_VERSION" \
    "$device_mapper_stage/usr/bin/dmsetup" dmsetup
install_program_from "cryptsetup-$CRYPTSETUP_VERSION" \
    "$cryptsetup_stage/usr/sbin/cryptsetup" cryptsetup
install_programs_from_directory "mdadm-$MDADM_VERSION" "$mdadm_stage/usr/bin" \
    mdadm mdmon
install_tree_if_present "mdadm-$MDADM_VERSION" \
    "$mdadm_stage/usr/lib/udev/rules.d" /usr/lib/udev/rules.d

install_program_from "udisks-$UDISKS_VERSION" \
    "$udisks_stage/usr/bin/udisksctl" udisksctl
install_rootfs_tree "udisks-$UDISKS_VERSION" \
    "$udisks_stage/usr/lib/udisks2" /usr/lib/udisks2

for tree_spec in \
    "udisks-$UDISKS_VERSION|$udisks_stage/etc/udisks2|/etc/udisks2" \
    "udisks-$UDISKS_VERSION|$udisks_stage/usr/share/dbus-1|/usr/share/dbus-1" \
    "udisks-$UDISKS_VERSION|$udisks_stage/usr/share/polkit-1|/usr/share/polkit-1" \
    "udisks-$UDISKS_VERSION|$udisks_stage/usr/share/udisks2|/usr/share/udisks2" \
    "udisks-$UDISKS_VERSION|$udisks_stage/usr/lib/udev/rules.d|/usr/lib/udev/rules.d" \
    "gvfs-$GVFS_VERSION|$gvfs_stage/usr/lib/gvfs|/usr/lib/gvfs" \
    "gvfs-$GVFS_VERSION|$gvfs_stage/usr/lib/gio/modules|/usr/lib/gio/modules" \
    "gvfs-$GVFS_VERSION|$gvfs_stage/usr/share/dbus-1|/usr/share/dbus-1" \
    "gvfs-$GVFS_VERSION|$gvfs_stage/usr/share/glib-2.0/schemas|/usr/share/glib-2.0/schemas" \
    "gvfs-$GVFS_VERSION|$gvfs_stage/usr/share/gvfs|/usr/share/gvfs"; do
    owner=${tree_spec%%|*}
    remainder=${tree_spec#*|}
    source_tree=${remainder%%|*}
    destination_tree=${remainder#*|}
    install_tree_if_present "$owner" "$source_tree" "$destination_tree"
done

shopt -s nullglob
for helper in "$gvfs_stage/usr/lib"/gvfsd* "$gvfs_stage/usr/lib"/gvfs-*-volume-monitor; do
    install_rootfs_file "gvfs-$GVFS_VERSION" "$helper" "/usr/lib/$(basename -- "$helper")"
done
shopt -u nullglob

log "Installing NetworkManager with the iwd Wi-Fi backend"
install_rootfs_file "iwd-$IWD_VERSION" \
    "$iwd_stage/usr/lib/iwd" /usr/lib/iwd
install_program_from "iwd-$IWD_VERSION" "$iwd_stage/usr/bin/iwctl" iwctl
install_tree_if_present "iwd-$IWD_VERSION" \
    "$iwd_stage/usr/share/dbus-1" /usr/share/dbus-1
install_programs_from_directory "NetworkManager-$NETWORKMANAGER_VERSION" \
    "$networkmanager_stage/usr/bin" NetworkManager nmcli nm-online
for helper in nm-daemon-helper nm-dhcp-helper nm-dispatcher nm-libnm-helper nm-priv-helper; do
    if [[ -x "$networkmanager_stage/usr/lib/$helper" ]]; then
        install_rootfs_file "NetworkManager-$NETWORKMANAGER_VERSION" \
            "$networkmanager_stage/usr/lib/$helper" "/usr/lib/$helper"
    fi
done
for tree_spec in \
    "NetworkManager-$NETWORKMANAGER_VERSION|$networkmanager_stage/usr/lib/NetworkManager|/usr/lib/NetworkManager" \
    "NetworkManager-$NETWORKMANAGER_VERSION|$networkmanager_stage/usr/lib/udev/rules.d|/usr/lib/udev/rules.d" \
    "NetworkManager-$NETWORKMANAGER_VERSION|$networkmanager_stage/usr/share/NetworkManager|/usr/share/NetworkManager" \
    "NetworkManager-$NETWORKMANAGER_VERSION|$networkmanager_stage/usr/share/dbus-1|/usr/share/dbus-1" \
    "NetworkManager-$NETWORKMANAGER_VERSION|$networkmanager_stage/usr/share/polkit-1|/usr/share/polkit-1"; do
    owner=${tree_spec%%|*}
    remainder=${tree_spec#*|}
    source_tree=${remainder%%|*}
    destination_tree=${remainder#*|}
    install_tree_if_present "$owner" "$source_tree" "$destination_tree"
done

log "Installing PipeWire, WirePlumber, and PulseAudio compatibility"
for program in pipewire pipewire-pulse pw-cli pw-cat pw-dump pw-link pw-metadata; do
    if [[ -x "$pipewire_stage/usr/bin/$program" ]]; then
        install_program_from "pipewire-$PIPEWIRE_VERSION" \
            "$pipewire_stage/usr/bin/$program" "$program"
    fi
done
for program in wireplumber wpctl; do
    if [[ -x "$wireplumber_stage/usr/bin/$program" ]]; then
        install_program_from "wireplumber-$WIREPLUMBER_VERSION" \
            "$wireplumber_stage/usr/bin/$program" "$program"
    fi
done
for program in pactl pacat pacmd; do
    if [[ -x "$pulseaudio_stage/usr/bin/$program" ]]; then
        install_program_from "pulseaudio-$PULSEAUDIO_VERSION" \
            "$pulseaudio_stage/usr/bin/$program" "$program"
    fi
done
for tree_spec in \
    "pulseaudio-$PULSEAUDIO_VERSION|$pulseaudio_stage/usr/lib/pulseaudio|/usr/lib/pulseaudio" \
    "pipewire-$PIPEWIRE_VERSION|$pipewire_stage/usr/lib/pipewire-0.3|/usr/lib/pipewire-0.3" \
    "pipewire-$PIPEWIRE_VERSION|$pipewire_stage/usr/lib/spa-0.2|/usr/lib/spa-0.2" \
    "pipewire-$PIPEWIRE_VERSION|$pipewire_stage/usr/share/pipewire|/usr/share/pipewire" \
    "pipewire-$PIPEWIRE_VERSION|$pipewire_stage/usr/share/alsa/alsa.conf.d|/usr/share/alsa/alsa.conf.d" \
    "pipewire-$PIPEWIRE_VERSION|$pipewire_stage/usr/lib/udev/rules.d|/usr/lib/udev/rules.d" \
    "wireplumber-$WIREPLUMBER_VERSION|$wireplumber_stage/usr/lib/wireplumber-0.5|/usr/lib/wireplumber-0.5" \
    "wireplumber-$WIREPLUMBER_VERSION|$wireplumber_stage/usr/share/wireplumber|/usr/share/wireplumber"; do
    owner=${tree_spec%%|*}
    remainder=${tree_spec#*|}
    source_tree=${remainder%%|*}
    destination_tree=${remainder#*|}
    install_tree_if_present "$owner" "$source_tree" "$destination_tree"
done

for tree_spec in \
    "elogind-$ELOGIND_VERSION|$elogind_stage/etc/elogind|/etc/elogind" \
    "elogind-$ELOGIND_VERSION|$elogind_stage/usr/share/dbus-1|/usr/share/dbus-1" \
    "elogind-$ELOGIND_VERSION|$elogind_stage/usr/share/polkit-1|/usr/share/polkit-1" \
    "elogind-$ELOGIND_VERSION|$elogind_stage/usr/lib/udev/rules.d|/usr/lib/udev/rules.d" \
    "polkit-$POLKIT_VERSION|$polkit_stage/etc/pam.d|/etc/pam.d" \
    "polkit-$POLKIT_VERSION|$polkit_stage/usr/share/dbus-1|/usr/share/dbus-1" \
    "polkit-$POLKIT_VERSION|$polkit_stage/usr/share/polkit-1|/usr/share/polkit-1" \
    "upower-$UPOWER_VERSION|$upower_stage/etc/UPower|/etc/UPower" \
    "upower-$UPOWER_VERSION|$upower_stage/usr/share/dbus-1|/usr/share/dbus-1" \
    "upower-$UPOWER_VERSION|$upower_stage/usr/share/polkit-1|/usr/share/polkit-1" \
    "upower-$UPOWER_VERSION|$upower_stage/usr/lib/udev/rules.d|/usr/lib/udev/rules.d"; do
    owner=${tree_spec%%|*}
    remainder=${tree_spec#*|}
    source_tree=${remainder%%|*}
    destination_tree=${remainder#*|}
    if [[ -d "$source_tree" ]]; then
        install_rootfs_tree "$owner" "$source_tree" "$destination_tree"
    fi
done

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
rm -f "$EFILINUX_ROOTFS/usr/share/dhcpcd/hooks/10-wpa_supplicant"
remove_rootfs_owner /usr/share/dhcpcd/hooks/10-wpa_supplicant

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
install_rootfs_library_family "elogind-$ELOGIND_VERSION" "$elogind_stage" 'libelogind.so.0*'
install_rootfs_library_family "polkit-$POLKIT_VERSION" "$polkit_stage" 'libpolkit-agent-1.so.0*'
install_rootfs_library_family "polkit-$POLKIT_VERSION" "$polkit_stage" 'libpolkit-gobject-1.so.0*'
install_rootfs_library_family "upower-$UPOWER_VERSION" "$upower_stage" 'libupower-glib.so.3*'
install_rootfs_library_family "device-mapper-$LVM2_VERSION" "$device_mapper_stage" 'libdevmapper.so.1.02*'
install_rootfs_library_family "cryptsetup-$CRYPTSETUP_VERSION" "$cryptsetup_stage" 'libcryptsetup.so.12*'
install_rootfs_library_family "libbytesize-$LIBBYTESIZE_VERSION" "$libbytesize_stage" 'libbytesize.so.1*'
install_library_families "libnvme-$LIBNVME_VERSION" "$libnvme_stage" \
    'libnvme.so.1*' \
    'libnvme-mi.so.1*'
install_library_families "libblockdev-$LIBBLOCKDEV_VERSION" "$libblockdev_stage" \
    'libblockdev.so.3*' \
    'libbd_crypto.so.3*' \
    'libbd_fs.so.3*' \
    'libbd_loop.so.3*' \
    'libbd_mdraid.so.3*' \
    'libbd_nvme.so.3*' \
    'libbd_part.so.3*' \
    'libbd_swap.so.3*' \
    'libbd_utils.so.3*'
install_rootfs_library_family "udisks-$UDISKS_VERSION" "$udisks_stage" 'libudisks2.so.0*'
install_rootfs_library_family "NetworkManager-$NETWORKMANAGER_VERSION" \
    "$networkmanager_stage" 'libnm.so.0*'
install_library_families "pulseaudio-$PULSEAUDIO_VERSION" "$pulseaudio_stage" \
    'libpulse.so.0*' \
    'libpulse-mainloop-glib.so.0*'
install_rootfs_library_family "pipewire-$PIPEWIRE_VERSION" \
    "$pipewire_stage" 'libpipewire-0.3.so.0*'
install_rootfs_library_family "wireplumber-$WIREPLUMBER_VERSION" \
    "$wireplumber_stage" 'libwireplumber-0.5.so.0*'

log "Creating runtime directories and runlevels"
mkdir -p \
    "$EFILINUX_ROOTFS/etc/cron.d" \
    "$EFILINUX_ROOTFS/root/.ssh" \
    "$EFILINUX_ROOTFS/home/user" \
    "$EFILINUX_ROOTFS/var/empty" \
    "$EFILINUX_ROOTFS/var/lib/dbus" \
    "$EFILINUX_ROOTFS/var/lib/dhcpcd" \
    "$EFILINUX_ROOTFS/var/lib/elogind" \
    "$EFILINUX_ROOTFS/var/lib/polkit-1" \
    "$EFILINUX_ROOTFS/var/lib/upower" \
    "$EFILINUX_ROOTFS/var/lib/udisks2" \
    "$EFILINUX_ROOTFS/var/lib/iwd" \
    "$EFILINUX_ROOTFS/var/lib/NetworkManager" \
    "$EFILINUX_ROOTFS/run/NetworkManager" \
    "$EFILINUX_ROOTFS/run/user" \
    "$EFILINUX_ROOTFS/var/log" \
    "$EFILINUX_ROOTFS/var/spool/cron" \
    "$EFILINUX_ROOTFS/var/spool/mail" \
    "$EFILINUX_ROOTFS/usr/libexec"

for runlevel in 0 1 2 3 4 5 6; do
    mkdir -p "$EFILINUX_ROOTFS/etc/rc.d/rc${runlevel}.d"
done

for runlevel in 2 3 4 5; do
    install_rootfs_symlink system-config ../init.d/syslog "/etc/rc.d/rc${runlevel}.d/S10syslog"
    install_rootfs_symlink system-config ../init.d/dbus "/etc/rc.d/rc${runlevel}.d/S20dbus"
    install_rootfs_symlink system-config ../init.d/elogind "/etc/rc.d/rc${runlevel}.d/S25elogind"
    install_rootfs_symlink system-config ../init.d/polkit "/etc/rc.d/rc${runlevel}.d/S35polkit"
    install_rootfs_symlink system-config ../init.d/cron "/etc/rc.d/rc${runlevel}.d/S40cron"
    install_rootfs_symlink system-config ../init.d/upower "/etc/rc.d/rc${runlevel}.d/S45upower"
    install_rootfs_symlink system-config ../init.d/iwd "/etc/rc.d/rc${runlevel}.d/S50iwd"
    install_rootfs_symlink system-config ../init.d/networkmanager "/etc/rc.d/rc${runlevel}.d/S55networkmanager"
    install_rootfs_symlink system-config ../init.d/udisks2 "/etc/rc.d/rc${runlevel}.d/S60udisks2"
    install_rootfs_symlink system-config ../init.d/sshd "/etc/rc.d/rc${runlevel}.d/S70sshd"
done

for runlevel in 0 6; do
    install_rootfs_symlink system-config ../init.d/sshd "/etc/rc.d/rc${runlevel}.d/K10sshd"
    install_rootfs_symlink system-config ../init.d/udisks2 "/etc/rc.d/rc${runlevel}.d/K15udisks2"
    install_rootfs_symlink system-config ../init.d/networkmanager "/etc/rc.d/rc${runlevel}.d/K20networkmanager"
    install_rootfs_symlink system-config ../init.d/iwd "/etc/rc.d/rc${runlevel}.d/K25iwd"
    install_rootfs_symlink system-config ../init.d/upower "/etc/rc.d/rc${runlevel}.d/K30upower"
    install_rootfs_symlink system-config ../init.d/cron "/etc/rc.d/rc${runlevel}.d/K35cron"
    install_rootfs_symlink system-config ../init.d/polkit "/etc/rc.d/rc${runlevel}.d/K40polkit"
    install_rootfs_symlink system-config ../init.d/elogind "/etc/rc.d/rc${runlevel}.d/K45elogind"
    install_rootfs_symlink system-config ../init.d/dbus "/etc/rc.d/rc${runlevel}.d/K50dbus"
    install_rootfs_symlink system-config ../init.d/syslog "/etc/rc.d/rc${runlevel}.d/K60syslog"
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
chmod 0750 "$EFILINUX_ROOTFS/home/user"
chown 1000:1000 "$EFILINUX_ROOTFS/home/user"
chmod 0755 "$EFILINUX_ROOTFS/var/empty"
touch \
    "$EFILINUX_ROOTFS/var/log/messages" \
    "$EFILINUX_ROOTFS/var/log/secure" \
    "$EFILINUX_ROOTFS/var/log/cron" \
    "$EFILINUX_ROOTFS/var/log/wtmp" \
    "$EFILINUX_ROOTFS/var/log/lastlog" \
    "$EFILINUX_ROOTFS/var/log/btmp"
chmod 0600 "$EFILINUX_ROOTFS/var/log/btmp"

if [[ -d "$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas" ]]; then
    rm -f "$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas/gschemas.compiled"
    remove_rootfs_owner /usr/share/glib-2.0/schemas/gschemas.compiled
    glib-compile-schemas "$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas"
    record_rootfs_owner system-schemas /usr/share/glib-2.0/schemas/gschemas.compiled
fi

if [[ -d "$EFILINUX_ROOTFS/usr/lib/gio/modules" ]]; then
    "$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2" \
        --library-path "$EFILINUX_ROOTFS/usr/lib" \
        "$EFILINUX_ROOTFS/usr/bin/gio-querymodules" \
        "$EFILINUX_ROOTFS/usr/lib/gio/modules"
    record_rootfs_owner gio-runtime /usr/lib/gio/modules/giomodule.cache
fi

strip_rootfs_elf
chmod 4755 \
    "$EFILINUX_ROOTFS/usr/bin/passwd" \
    "$EFILINUX_ROOTFS/usr/bin/su" \
    "$EFILINUX_ROOTFS/usr/bin/newgrp" \
    "$EFILINUX_ROOTFS/usr/bin/crontab" \
    "$EFILINUX_ROOTFS/usr/bin/pkexec" \
    "$EFILINUX_ROOTFS/usr/lib/polkit-1/polkit-agent-helper-1" \
    "$EFILINUX_ROOTFS/usr/libexec/dbus-daemon-launch-helper"

if find "$EFILINUX_ROOTFS/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -print -quit | grep -q .; then
    die "OpenSSH host keys must not be embedded in the image"
fi

log "System rootfs assembly complete"
