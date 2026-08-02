#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=system-init
pkgver=1
sysroot=false

depends=(busybox efilinux-live fsmeta-replay sysvinit)
builddepends=()
makedepends=(install)

prepare() {
    :
}

build() {
    install -d -m0755 "$develdir"
    cat > "$develdir/init" <<'INIT'
#!/usr/bin/busybox sh

exec </dev/console >/dev/console 2>&1

/etc/rc.d/init.d/mountvirtfs start || {
    echo "early virtual filesystem setup failed" >&2
    exec /usr/bin/busybox sh
}
exec /usr/libexec/efilinux-live-root "$@"
INIT
    chmod 0755 "$develdir/init"
}

package() {
    :
}

recipe_main "$@"
