#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command readelf
ensure_directories

busybox_staging="$EFILINUX_BUILD/staging/busybox"
rootfs_directory="$EFILINUX_ROOTFS"
busybox_binary="$busybox_staging/bin/busybox"

[[ -x "$busybox_binary" ]] || die "BusyBox staging tree does not exist"
reset_directory "$rootfs_directory"
mkdir -p "$(dirname -- "$EFILINUX_ROOTFS_OWNERS")"
: > "$EFILINUX_ROOTFS_OWNERS"

log "Creating merged-/usr target rootfs"
mkdir -p \
    "$rootfs_directory/usr/bin" \
    "$rootfs_directory/usr/lib" \
    "$rootfs_directory/dev" \
    "$rootfs_directory/proc" \
    "$rootfs_directory/sys" \
    "$rootfs_directory/run" \
    "$rootfs_directory/tmp" \
    "$rootfs_directory/etc" \
    "$rootfs_directory/root"

ln -s usr/bin "$rootfs_directory/bin"
ln -s usr/bin "$rootfs_directory/sbin"
ln -s usr/lib "$rootfs_directory/lib"
ln -s usr/lib "$rootfs_directory/lib64"
ln -s bin "$rootfs_directory/usr/sbin"
chmod 1777 "$rootfs_directory/tmp"

cp "$busybox_binary" "$rootfs_directory/usr/bin/busybox"
record_rootfs_owner busybox /usr/bin/busybox
while IFS= read -r applet_name; do
    [[ "$applet_name" == busybox ]] && continue
    ln -s busybox "$rootfs_directory/usr/bin/$applet_name"
    record_rootfs_owner busybox "/usr/bin/$applet_name"
done < <(
    find "$busybox_staging" -type l -printf '%f\n' | sort -u
)

copy_program() {
    local package=$1
    local program=$2
    local source="$EFILINUX_BUILD/staging/$package/usr/bin/$program"
    install_rootfs_program "$package" "$source" "$program"
}

copy_runtime_libraries() {
    local package=$1
    local pattern=$2
    install_rootfs_library_family \
        "$package" \
        "$EFILINUX_BUILD/staging/$package" \
        "$pattern"
}

copy_runtime_libraries zlib 'libz.so.1*'
copy_runtime_libraries xz 'liblzma.so.5*'
copy_runtime_libraries zstd 'libzstd.so.1*'

for program in xz unxz xzcat; do
    copy_program xz "$program"
done
for program in zstd unzstd zstdcat; do
    copy_program zstd "$program"
done

copy_glibc_runtime_file() {
    local file_name=$1
    local source_file="$EFILINUX_SYSROOT/usr/lib/$file_name"

    [[ -e "$source_file" ]] || die "glibc runtime file is missing: $file_name"
    local resolved="$EFILINUX_BUILD/staging/rootfs-glibc/$file_name"
    mkdir -p "$(dirname -- "$resolved")"
    cp -aL "$source_file" "$resolved"
    install_rootfs_file glibc "$resolved" "/usr/lib/$file_name"
}

for runtime_file in \
    ld-linux-x86-64.so.2 \
    libc.so.6 \
    libdl.so.2 \
    libm.so.6 \
    libnss_dns.so.2 \
    libnss_files.so.2 \
    libpthread.so.0 \
    libresolv.so.2 \
    librt.so.1; do
    copy_glibc_runtime_file "$runtime_file"
done

cat > "$rootfs_directory/init" <<'INIT'
#!/bin/busybox sh

export PATH=/usr/bin
export HOME=/root
export TERM=linux

/usr/bin/mount -t proc proc /proc
/usr/bin/mount -t sysfs sysfs /sys
/usr/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || /usr/bin/true

/usr/bin/mdev -s
/usr/bin/mdev -d >/dev/null 2>&1 &
/usr/bin/hostname efilinux

/usr/bin/printf '\nEFI Linux initial runtime\n'
/usr/bin/printf '%s\n\n' "$(/usr/bin/busybox | /usr/bin/head -n 1)"
exec /usr/bin/setsid /usr/bin/cttyhack /usr/bin/sh
INIT
chmod 0755 "$rootfs_directory/init"

cat > "$rootfs_directory/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/sh
PASSWD
cat > "$rootfs_directory/etc/group" <<'GROUP'
root:x:0:
GROUP
cat > "$rootfs_directory/etc/nsswitch.conf" <<'NSSWITCH'
passwd: files
group: files
shadow: files
hosts: files dns
NSSWITCH
cat > "$rootfs_directory/etc/hosts" <<'HOSTS'
127.0.0.1 localhost efilinux
::1 localhost efilinux
HOSTS
cat > "$rootfs_directory/etc/host.conf" <<'HOSTCONF'
multi on
HOSTCONF
cat > "$rootfs_directory/etc/resolv.conf" <<'RESOLV'
# Populated by the network configuration layer.
RESOLV
cat > "$rootfs_directory/etc/mdev.conf" <<'MDEV'
$MODALIAS=.* 0:0 660 @/usr/bin/modprobe "$MODALIAS"
MDEV

log "Writing initramfs device manifest"
cat > "$EFILINUX_INITRAMFS_DEVICES" <<'DEVICES'
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
DEVICES
