#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=recovery-launchers
pkgver=3
depends=(
    bash clonezilla coreutils doas efibooteditor efibootmgr gsmartcontrol kdiskmark mc ncdu
    networkmanager-nmtui nwipe polkit testdisk xfce
)
builddepends=()
makedepends=()
prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
}
build() {
    cp -a "$srcdir/files/." "$develdir/"
}
devel() { :; }
package() {
    package_keep \
        /usr/bin/ \
        /usr/libexec/recovery-privileged-launch \
        /usr/share/applications/ \
        /usr/share/polkit-1/actions/org.efilinux.recovery.policy
}
recipe_main "$@"
