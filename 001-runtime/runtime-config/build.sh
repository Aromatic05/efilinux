#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=runtime-config
pkgver=1
sysroot=false

depends=()
builddepends=()
makedepends=(install)

prepare() {
    :
}

build() {
    install -d -m0755 "$develdir/etc"
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
    chmod 0644 "$develdir/etc/"*
}

package() {
    :
}

recipe_main "$@"
