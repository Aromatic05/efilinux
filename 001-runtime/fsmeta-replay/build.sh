#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=fsmeta-replay
pkgver=1
sysroot=false

depends=(acl glibc libcap)
builddepends=(linux-headers)
makedepends=(gcc install)

prepare() {
    input_file "$recipedir/files/fsmeta-replay.c" "$srcdir/fsmeta-replay.c"
}

build() {
    install -d -m0755 "$develdir/usr/bin"
    "$CC" \
        $CPPFLAGS \
        $CFLAGS \
        -std=c11 \
        -Wall \
        -Wextra \
        -Werror \
        "$srcdir/fsmeta-replay.c" \
        -o "$develdir/usr/bin/fsmeta-replay" \
        $LDFLAGS \
        -lacl \
        -lcap
}

devel() {
    strip_all "$develdir/usr/bin/fsmeta-replay"
}

package() {
    :
}

recipe_main "$@"
