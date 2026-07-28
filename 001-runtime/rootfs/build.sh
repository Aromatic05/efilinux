#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command readelf
ensure_directories

staging_directory="$EFILINUX_BUILD/staging/busybox"
rootfs_directory="$EFILINUX_TARGET/rootfs"
busybox_binary="$staging_directory/bin/busybox"

[[ -x "$busybox_binary" ]] || die "BusyBox staging tree does not exist"
reset_directory "$rootfs_directory"

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
while IFS= read -r applet_name; do
    [[ "$applet_name" == busybox ]] && continue
    ln -s busybox "$rootfs_directory/usr/bin/$applet_name"
done < <(
    find "$staging_directory" -type l -printf '%f\n' | sort -u
)

copy_glibc_runtime_file() {
    local file_name=$1
    local source_file="$EFILINUX_SYSROOT/usr/lib/$file_name"

    [[ -e "$source_file" ]] || die "glibc runtime file is missing: $file_name"
    cp -aL "$source_file" "$rootfs_directory/usr/lib/$file_name"
}

interpreter=$(LC_ALL=C readelf --program-headers "$rootfs_directory/usr/bin/busybox" |
    sed -n 's@.*Requesting program interpreter: \(.*\)]@\1@p')
[[ -n "$interpreter" ]] || die "BusyBox ELF interpreter was not found"
copy_glibc_runtime_file "$(basename -- "$interpreter")"

while IFS= read -r library_name; do
    [[ -z "$library_name" ]] && continue
    copy_glibc_runtime_file "$library_name"
done < <(
    LC_ALL=C readelf --dynamic "$rootfs_directory/usr/bin/busybox" |
        sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'
)

cat > "$rootfs_directory/init" <<'INIT'
#!/bin/busybox sh

/usr/bin/mount -t proc proc /proc
/usr/bin/mount -t sysfs sysfs /sys
/usr/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

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

log "Writing initramfs device manifest"
cat > "$EFILINUX_INITRAMFS_DEVICES" <<'DEVICES'
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
DEVICES
