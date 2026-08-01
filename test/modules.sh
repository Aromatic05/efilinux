#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/modules/lib/module.sh"

require_command find mksquashfs unsquashfs
ensure_directories

work="$EFILINUX_TEST/module-framework"
artifact="$ROOT/modules/output/901-valid.zxm"
trap 'rm -f -- "$artifact"' EXIT
valid="$work/901-valid"
cross="$work/902-cross"
outside="$work/903-outside"
conflict="$work/904-conflict"
reset_directory "$work"

make_recipe() {
    local directory=$1
    local name=$2
    local dependencies=$3
    local build_body=$4

    mkdir -p "$directory/$name"
    cat > "$directory/$name/build.sh" <<EOF_RECIPE
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=$name
pkgver=1
depends=($dependencies)
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
$build_body
}
package() { :; }
recipe_main "\$@"
EOF_RECIPE
    chmod 0755 "$directory/$name/build.sh"
}

make_module() {
    local directory=$1
    local id=$2
    local components=$3
    local profile=$4

    cat > "$directory/build.sh" <<EOF_MODULE
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/modules/lib/module.sh"
module_id=$id
module_version=1
module_description='module framework behavior test'
module_max_size=1048576
module_components=($components)
module_main "\$@"
EOF_MODULE
    printf '%s\n' "$profile" > "$directory/module.packages"
    chmod 0755 "$directory/build.sh"
}

make_recipe "$valid" foundation 'glibc' '
    install -d -m0755 "$develdir/usr/bin"
    cat > "$develdir/usr/bin/foundation-command" <<"SCRIPT"
#!/bin/sh
printf "%s\\n" foundation-ready
SCRIPT
    chmod 0755 "$develdir/usr/bin/foundation-command"'
make_recipe "$valid" consumer 'foundation glibc' '
    result=$("$EFILINUX_SYSROOT/usr/bin/foundation-command")
    install -d -m0755 "$develdir/usr/bin"
    cat > "$develdir/usr/bin/consumer-command" <<SCRIPT
#!/bin/sh
printf "%s\\n" "consumer-used-$result"
SCRIPT
    chmod 0755 "$develdir/usr/bin/consumer-command"'
make_module "$valid" framework-valid 'foundation consumer' consumer
rm -f -- "$artifact"
"$valid/build.sh"
[[ -f "$artifact" ]] || die "module framework produced no artifact"
ZXMOD_LIBRARY="$ROOT/005-utils/zxmod/files/usr/lib/zxmod/common.sh" \
    "$ROOT/005-utils/zxmod/files/usr/bin/zxmod" inspect "$artifact" >/dev/null
extract="$work/extracted"
unsquashfs -quiet -dest "$extract" "$artifact"
foundation=$(find "$extract" -type f -name foundation-command -print -quit)
consumer=$(find "$extract" -type f -name consumer-command -print -quit)
[[ $(/bin/sh "$foundation") == foundation-ready ]]
[[ $(/bin/sh "$consumer") == consumer-used-foundation-ready ]]

make_recipe "$cross" cross-consumer 'consumer glibc' '
    install -Dm0755 /dev/null "$develdir/usr/bin/cross-consumer"'
make_module "$cross" framework-cross cross-consumer cross-consumer
if "$cross/build.sh" >/dev/null 2>&1; then
    die "module framework accepted a dependency supplied only by another module"
fi

make_recipe "$outside" outside 'glibc' '
    install -Dm0644 /dev/null "$develdir/etc/outside.conf"'
make_module "$outside" framework-outside outside outside
if "$outside/build.sh" >/dev/null 2>&1; then
    die "module framework accepted payload outside /usr and /opt"
fi

make_recipe "$conflict" conflict 'glibc' '
    install -Dm0755 /dev/null "$develdir/usr/bin/bash"'
make_module "$conflict" framework-conflict conflict conflict
if "$conflict/build.sh" >/dev/null 2>&1; then
    die "module framework accepted a payload that replaces a base command"
fi

log "Module dependency use, executable payload, isolation, path boundary, and base conflict behavior passed"
