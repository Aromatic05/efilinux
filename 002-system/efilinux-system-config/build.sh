#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=efilinux-system-config
pkgver=1
sysroot=false

depends=(base-files bash bash-completion doas efilinux-live)
builddepends=()
makedepends=(awk install openssl)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    local account password_hash prefix runlevel service
    local -a start_services=(syslog dbus elogind polkit cron upower iwd networkmanager udisks2 sshd)
    local -a stop_services=(sshd udisks2 networkmanager iwd upower cron polkit elogind dbus syslog)

    cp -a "$srcdir/files/." "$develdir/"
    find "$develdir/etc" -type f -exec chmod 0644 {} +

    for account in root user; do
        password_hash=$(openssl passwd -6 -salt "$account" "$account")
        awk -F: -v OFS=: -v account="$account" -v hash="$password_hash" \
            '$1 == account { $2 = hash } { print }' \
            "$develdir/etc/shadow" > "$develdir/etc/shadow.next"
        mv "$develdir/etc/shadow.next" "$develdir/etc/shadow"
    done

    install -d -m0755 \
        "$develdir/etc/cron.d" \
        "$develdir/var/empty" \
        "$develdir/var/lib/dbus" \
        "$develdir/var/lib/dhcpcd" \
        "$develdir/var/lib/elogind" \
        "$develdir/var/lib/polkit-1" \
        "$develdir/var/lib/upower" \
        "$develdir/var/lib/udisks2" \
        "$develdir/var/lib/iwd" \
        "$develdir/var/lib/NetworkManager" \
        "$develdir/run/NetworkManager" \
        "$develdir/run/user" \
        "$develdir/var/log" \
        "$develdir/var/spool/cron" \
        "$develdir/var/spool/mail" \
        "$develdir/usr/libexec"
    install -d -m0750 "$develdir/home/user"
    chown 1000:1000 "$develdir/home/user"
    install -d -m0700 "$develdir/root/.ssh"

    for runlevel in 0 1 2 3 4 5 6; do
        install -d -m0755 "$develdir/etc/rc.d/rc${runlevel}.d"
    done
    for runlevel in 2 3 4 5; do
        for service in "${start_services[@]}"; do
            case $service in
                syslog) prefix=10 ;;
                dbus) prefix=20 ;;
                elogind) prefix=25 ;;
                polkit) prefix=35 ;;
                cron) prefix=40 ;;
                upower) prefix=45 ;;
                iwd) prefix=50 ;;
                networkmanager) prefix=55 ;;
                udisks2) prefix=60 ;;
                sshd) prefix=70 ;;
            esac
            ln -s "../init.d/$service" "$develdir/etc/rc.d/rc${runlevel}.d/S${prefix}${service}"
        done
    done
    for runlevel in 0 6; do
        prefix=10
        for service in "${stop_services[@]}"; do
            ln -s "../init.d/$service" "$develdir/etc/rc.d/rc${runlevel}.d/K${prefix}${service}"
            prefix=$((prefix + 5))
        done
    done

    ln -s /run "$develdir/var/run"
    ln -s /run/lock "$develdir/var/lock"
    ln -s /etc/machine-id "$develdir/var/lib/dbus/machine-id"
    ln -s /proc/self/mounts "$develdir/etc/mtab"

    chmod 0755 \
        "$develdir/etc/rc.d/rcS" \
        "$develdir/etc/rc.d/rc" \
        "$develdir/etc/rc.d/rc.shutdown" \
        "$develdir/etc/rc.d/init.d/"*
    chmod 0600 "$develdir/etc/shadow" "$develdir/etc/gshadow"

    touch \
        "$develdir/var/log/messages" \
        "$develdir/var/log/secure" \
        "$develdir/var/log/cron" \
        "$develdir/var/log/wtmp" \
        "$develdir/var/log/lastlog" \
        "$develdir/var/log/btmp"
    chmod 0600 "$develdir/var/log/btmp"
}

package() {
    :
}

recipe_main "$@"
