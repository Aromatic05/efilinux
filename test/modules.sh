#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/modules/lib/module.sh"

require_command mksquashfs unsquashfs
ensure_directories

work="$EFILINUX_TEST/module-framework"
module_directory="$work/999-framework-test"
module_profile="$module_directory/module.packages"
reset_directory "$work"
mkdir -p "$module_directory"
printf 'spice-protocol\n' > "$module_profile"

module_id=framework-test
module_version=1
module_description='module framework integration test'
module_max_size=1048576
module_compose "$module_directory"

artifact="$EFILINUX_TARGET/modules/999-framework-test.zxm"
[[ -f "$artifact" ]] || die "module framework did not produce a ZXM artifact"
unsquashfs -cat "$artifact" metadata/manifest | grep -Fxq 'id=framework-test'
unsquashfs -cat "$artifact" metadata/manifest | grep -Fxq 'version=1'
unsquashfs -cat "$artifact" root/opt/efilinux/modules/framework-test/packages.tsv |
    grep -Fq $'spice-protocol\t0.14.5'
unsquashfs -cat "$artifact" root/usr/share/efilinux/build-components/spice-protocol.stamp >/dev/null

mkdir -p "$work/conflict/usr/bin" "$work/outside/etc"
printf 'conflict\n' > "$work/conflict/usr/bin/bash"
printf 'outside\n' > "$work/outside/etc/example"
if (module_validate_base_path conflict "$work/conflict" /usr/bin/bash) 2>/dev/null; then
    die "module framework accepted a base file conflict"
fi
if (module_validate_base_path outside "$work/outside" /etc/example) 2>/dev/null; then
    die "module framework accepted a path outside /usr and /opt"
fi

rm -f -- "$artifact"
log "module profile resolution, ZXM packaging, metadata, and conflict checks passed"
