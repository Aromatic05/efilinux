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

depends=(busybox fsmeta-replay sysvinit)
builddepends=()
makedepends=(install)

prepare() {
    :
}

build() {
    install -d -m0755 "$develdir"
    cat > "$develdir/init" <<'INIT'
#!/usr/bin/busybox sh

/usr/bin/fsmeta-replay || {
    status=$?
    echo "fsmeta-replay failed with status $status" >&2
    exec /usr/bin/busybox sh
}

exec /usr/bin/init "$@"
INIT
    chmod 0755 "$develdir/init"
}

package() {
    :
}

recipe_main "$@"
