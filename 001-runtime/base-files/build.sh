#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=base-files
pkgver=1
sysroot=false

depends=(busybox kmod)
builddepends=()
makedepends=(install mknod)

prepare() {
    :
}

build() {
    install -d -m0755 \
        "$develdir/dev" \
        "$develdir/etc" \
        "$develdir/proc" \
        "$develdir/root" \
        "$develdir/run" \
        "$develdir/sys" \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
    install -d -m1777 "$develdir/tmp"

    ln -s usr/bin "$develdir/bin"
    ln -s usr/bin "$develdir/sbin"
    ln -s usr/lib "$develdir/lib"
    ln -s usr/lib "$develdir/lib64"
    ln -s bin "$develdir/usr/sbin"

    mknod -m0600 "$develdir/dev/console" c 5 1
    mknod -m0666 "$develdir/dev/null" c 1 3

    cat > "$develdir/init" <<'INIT'
#!/usr/bin/busybox sh

export PATH=/usr/bin
export HOME=/root
export TERM=linux

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

mdev -s
mdev -d >/dev/null 2>&1 &
hostname efilinux

printf '\nEFI Linux initial runtime\n'
printf '%s\n\n' "$(busybox | head -n 1)"
exec setsid cttyhack sh
INIT
    chmod 0755 "$develdir/init"

    cat > "$develdir/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/sh
PASSWD
    cat > "$develdir/etc/group" <<'GROUP'
root:x:0:
GROUP
    cat > "$develdir/etc/nsswitch.conf" <<'NSSWITCH'
passwd: files
group: files
shadow: files
hosts: files dns
NSSWITCH
    cat > "$develdir/etc/hosts" <<'HOSTS'
127.0.0.1 localhost efilinux
::1 localhost efilinux
HOSTS
    cat > "$develdir/etc/host.conf" <<'HOSTCONF'
multi on
HOSTCONF
    cat > "$develdir/etc/resolv.conf" <<'RESOLV'
# Populated by the network configuration layer.
RESOLV
    cat > "$develdir/etc/mdev.conf" <<'MDEV'
$MODALIAS=.* 0:0 660 @/usr/bin/modprobe "$MODALIAS"
MDEV
    chmod 0644 \
        "$develdir/etc/passwd" \
        "$develdir/etc/group" \
        "$develdir/etc/nsswitch.conf" \
        "$develdir/etc/hosts" \
        "$develdir/etc/host.conf" \
        "$develdir/etc/resolv.conf" \
        "$develdir/etc/mdev.conf"
}

package() {
    :
}

recipe_main "$@"
