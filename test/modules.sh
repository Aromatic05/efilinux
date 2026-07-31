#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/modules/lib/module.sh"

require_command mksquashfs sha256sum unsquashfs
ensure_directories

work="$EFILINUX_TEST/module-framework"
module_a="$work/999-module-a"
module_b="$work/998-module-b"
base_index_hash=$(sha256sum "$MODULE_BASE_PACKAGE_INDEX" | awk '{print $1}')
base_index_mtime=$(stat -c %Y "$MODULE_BASE_PACKAGE_INDEX")
base_sysroot_count=$(find "$MODULE_BASE_SYSROOT" -xdev -printf . | wc -c)
base_rootfs_count=$(find "$MODULE_BASE_ROOTFS" -xdev -printf . | wc -c)

reset_directory "$work"
[[ ! -e "$EFILINUX_BUILD/modules" ]] || die "shared build/modules directory must not exist"
[[ ! -e "$MODULE_BASE_SYSROOT/usr/share/module-framework-test" ]]
[[ ! -e "$MODULE_BASE_ROOTFS/usr/share/module-framework-test" ]]

mkdir -p "$module_a/foundation" "$module_a/consumer"
cat > "$module_a/foundation/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=foundation
pkgver=1
depends=(glibc)
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    install -Dm0644 /dev/null \
        "\$develdir/usr/share/module-framework-test/foundation.txt"
}
package() { :; }
recipe_main "\$@"
EOF
cat > "$module_a/consumer/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=consumer
pkgver=1
depends=(foundation glibc)
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    [[ -f "\$EFILINUX_SYSROOT/usr/share/module-framework-test/foundation.txt" ]] ||
        die "module-local dependency was not installed into the module sysroot"
    install -Dm0644 /dev/null \
        "\$develdir/usr/share/module-framework-test/consumer.txt"
}
package() { :; }
recipe_main "\$@"
EOF
cat > "$module_a/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/modules/lib/module.sh"
module_id=framework-a
module_version=1
module_description='module framework isolation test A'
module_max_size=1048576
module_components=(foundation consumer)
module_main "\$@"
EOF
printf 'consumer\n' > "$module_a/module.packages"
chmod 0755 \
    "$module_a/build.sh" \
    "$module_a/foundation/build.sh" \
    "$module_a/consumer/build.sh"

"$module_a/build.sh"
artifact_a="$module_a/output/999-module-a.zxm"
[[ -f "$artifact_a" ]] || die "module artifact was not written inside the module directory"
[[ -d "$module_a/build/recipes" ]]
[[ -f "$module_a/packages/index.tsv" ]]
[[ -d "$module_a/sysroot" ]]
[[ ! -e "$EFILINUX_BUILD/modules" ]]
[[ ! -e "$EFILINUX_TARGET/modules/999-module-a.zxm" ]]

unsquashfs -cat "$artifact_a" metadata/manifest | grep -Fxq 'id=framework-a'
unsquashfs -cat "$artifact_a" metadata/manifest | grep -Fxq 'version=1'
packages=$(unsquashfs -cat \
    "$artifact_a" root/opt/efilinux/modules/framework-a/packages.tsv)
grep -Fqx $'foundation\t1' <<<"$packages"
grep -Fqx $'consumer\t1' <<<"$packages"
! grep -Fq $'glibc\t' <<<"$packages"
unsquashfs -cat \
    "$artifact_a" root/usr/share/module-framework-test/foundation.txt >/dev/null
unsquashfs -cat \
    "$artifact_a" root/usr/share/module-framework-test/consumer.txt >/dev/null

mkdir -p "$module_b/cross-consumer"
cat > "$module_b/cross-consumer/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=cross-consumer
pkgver=1
depends=(consumer glibc)
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    install -Dm0644 /dev/null \
        "\$develdir/usr/share/module-framework-test/cross-consumer.txt"
}
package() { :; }
recipe_main "\$@"
EOF
cat > "$module_b/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/modules/lib/module.sh"
module_id=framework-b
module_version=1
module_description='module framework isolation test B'
module_max_size=1048576
module_components=(cross-consumer)
module_main "\$@"
EOF
printf 'cross-consumer\n' > "$module_b/module.packages"
chmod 0755 "$module_b/build.sh" "$module_b/cross-consumer/build.sh"

if "$module_b/build.sh" >"$work/module-b.stdout" 2>"$work/module-b.stderr"; then
    die "module B accepted a dependency supplied only by module A"
fi
grep -Fq \
    'module component cross-consumer depends on unavailable package consumer; modules cannot depend on other modules' \
    "$work/module-b.stderr"
[[ ! -e "$module_b/output/998-module-b.zxm" ]]

mkdir -p "$work/conflict/usr/bin" "$work/outside/etc"
printf 'conflict\n' > "$work/conflict/usr/bin/bash"
printf 'outside\n' > "$work/outside/etc/example"
if (module_validate_base_path conflict "$work/conflict" /usr/bin/bash) 2>/dev/null; then
    die "module framework accepted a base file conflict"
fi
if (module_validate_base_path outside "$work/outside" /etc/example) 2>/dev/null; then
    die "module framework accepted a path outside /usr and /opt"
fi

[[ $(sha256sum "$MODULE_BASE_PACKAGE_INDEX" | awk '{print $1}') == "$base_index_hash" ]]
[[ $(stat -c %Y "$MODULE_BASE_PACKAGE_INDEX") == "$base_index_mtime" ]]
[[ $(find "$MODULE_BASE_SYSROOT" -xdev -printf . | wc -c) == "$base_sysroot_count" ]]
[[ $(find "$MODULE_BASE_ROOTFS" -xdev -printf . | wc -c) == "$base_rootfs_count" ]]
[[ ! -e "$MODULE_BASE_SYSROOT/usr/share/module-framework-test" ]]
[[ ! -e "$MODULE_BASE_ROOTFS/usr/share/module-framework-test" ]]
[[ ! -e "$EFILINUX_BUILD/modules" ]]

log "module-local workspaces, self-contained ZXM output, base-only external dependencies, and cross-module rejection passed"
