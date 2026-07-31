#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

export EFILINUX_ROOT="$ROOT"
export EFILINUX_DOWNLOADS="$work/downloads"
export EFILINUX_PACKAGES="$work/packages"
export EFILINUX_BUILD="$work/build"
export EFILINUX_TARGET="$work/target"
export EFILINUX_ROOTFS="$work/target/rootfs"
export EFILINUX_SYSROOT="$work/sysroot"
export EFILINUX_LOGS="$work/build/logs"
export EFILINUX_STATE="$work/build/state"
export EFILINUX_TEST="$work/build/test"
export EFILINUX_PACKAGE_INDEX="$work/packages/index.tsv"
export EFILINUX_PACKAGE_WORK="$work/build/packages"

recipe_directory="$work/mock"
mkdir -p "$recipe_directory"
printf 'runtime payload\n' > "$recipe_directory/payload.txt"

cat > "$recipe_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"

pkgname=mock
pkgver=1.0

depends=()
builddepends=()
makedepends=(grep install)

package_capability /usr/bin/mock-cap cap_net_raw=ep
package_acl /usr/share/mock/payload.txt 'user::rw-,user:1234:r--,group::r--,mask::r--,other::---'

prepare() {
    input_file "\$recipedir/payload.txt" "\$srcdir/payload.txt"
}

build() {
    printf 'build\n' >> "$work/mock-builds"
    install -Dm0644 "\$srcdir/payload.txt" "\$develdir/usr/share/mock/payload.txt"
    install -Dm0644 "\$srcdir/payload.txt" "\$develdir/usr/share/mock/optional.txt"
    install -Dm0644 "\$srcdir/payload.txt" "\$develdir/usr/include/mock.h"
    install -Dm0755 "\$srcdir/payload.txt" "\$develdir/usr/bin/mock-cap"
}

check() {
    grep -Fxq 'runtime payload' "\$develdir/usr/share/mock/payload.txt"
    touch "\$recipework/check-ran"
}

devel() {
    chmod 0640 "\$develdir/usr/share/mock/payload.txt"
}

package() {
    rm -rf "\$pkgdir/usr/include"
}

recipe_main "\$@"
EOF
chmod 0755 "$recipe_directory/build.sh"

metadata=$($recipe_directory/build.sh --print-metadata)
grep -Fq '"pkgname":"mock"' <<<"$metadata"
grep -Fq 'input-file=' <<<"$metadata"
grep -Fq '"capabilities":["/usr/bin/mock-cap\tcap_net_raw=ep"]' <<<"$metadata"
grep -Fq '"acls":["/usr/share/mock/payload.txt\tuser::rw-,user:1234:r--,group::r--,mask::r--,other::---"]' <<<"$metadata"
[[ ! -e "$work/build" ]] || {
    printf 'metadata query created build state\n' >&2
    exit 1
}

alternate_metadata=$(
    EFILINUX_BUILD="$work/alternate-build" \
    EFILINUX_DOWNLOADS="$work/alternate-downloads" \
        "$recipe_directory/build.sh" --print-metadata
)
metadata_key=$(sed -n 's/.*"recipe_key":"\([^"]*\)".*/\1/p' <<<"$metadata")
alternate_metadata_key=$(sed -n 's/.*"recipe_key":"\([^"]*\)".*/\1/p' <<<"$alternate_metadata")
[[ "$metadata_key" == "$alternate_metadata_key" ]] || {
    printf 'recipe key depends on build or download directory location\n' >&2
    exit 1
}
[[ ! -e "$work/alternate-build" && ! -e "$work/alternate-downloads" ]] || {
    printf 'alternate metadata query created build state\n' >&2
    exit 1
}

"$recipe_directory/build.sh" --no-deps
[[ -f "$work/build/recipes/mock-1.0/check-ran" ]] || {
    printf 'check() did not run by default\n' >&2
    exit 1
}

archive=$(awk -F '\t' 'NR == 2 { print $5 }' "$EFILINUX_PACKAGE_INDEX")
archive="$EFILINUX_PACKAGES/$archive"
[[ -f "$archive" ]]
grep -Fxq '/usr/share/mock/payload.txt' < <(tar -xOf "$archive" .INSTALL)
grep -Fxq '/usr/share/mock/optional.txt' < <(tar -xOf "$archive" .INSTALL)
if grep -Fq '/usr/include/mock.h' < <(tar -xOf "$archive" .INSTALL); then
    printf 'package subset retained a deleted development file\n' >&2
    exit 1
fi
grep -Fxq '/usr/include/mock.h' < <(tar -xOf "$archive" .FILELIST)
grep -Fxq '/etc/filemeta/acls/mock' < <(tar -xOf "$archive" .INSTALL)
grep -Fxq '/etc/filemeta/caps/mock' < <(tar -xOf "$archive" .INSTALL)
grep -Fxq $'/usr/bin/mock-cap\tcap_net_raw=ep' \
    < <(tar -xOf "$archive" devel/etc/filemeta/caps/mock)
grep -Fq $'/usr/share/mock/payload.txt\tuser::rw-,user:1234:r--' \
    < <(tar -xOf "$archive" devel/etc/filemeta/acls/mock)

source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
materialized="$work/materialized"
package_materialize mock "$materialized"
[[ -f "$materialized/usr/share/mock/payload.txt" ]]
[[ -f "$materialized/etc/filemeta/acls/mock" ]]
[[ -f "$materialized/etc/filemeta/caps/mock" ]]
[[ ! -e "$materialized/usr/include/mock.h" ]]
[[ $(stat -c '%a' "$materialized/usr/share/mock/payload.txt") == 640 ]]

archive_count_before=$(find "$EFILINUX_PACKAGES" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
"$recipe_directory/build.sh" --no-deps
archive_count_after=$(find "$EFILINUX_PACKAGES" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
[[ "$archive_count_before" == "$archive_count_after" ]] || {
    printf 'cache reuse created another archive\n' >&2
    exit 1
}

python3 - "$recipe_directory/build.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''package() {
    rm -rf "$pkgdir/usr/include"
}'''
new = '''package() {
    rm -rf "$pkgdir/usr/include"
    rm -f "$pkgdir/usr/share/mock/optional.txt"
}'''
if text.count(old) != 1:
    raise SystemExit('mock package() fixture changed unexpectedly')
path.write_text(text.replace(old, new))
PY

"$recipe_directory/build.sh" --repackage
[[ $(wc -l < "$work/mock-builds") == 1 ]] || {
    printf 'repackage reran build()\n' >&2
    exit 1
}
archive=$(awk -F '\t' 'NR == 2 { print $5 }' "$EFILINUX_PACKAGE_INDEX")
archive="$EFILINUX_PACKAGES/$archive"
if grep -Fxq '/usr/share/mock/optional.txt' < <(tar -xOf "$archive" .INSTALL); then
    printf 'repackage did not apply the new package subset\n' >&2
    exit 1
fi
grep -Fxq '/usr/share/mock/optional.txt' < <(tar -xOf "$archive" .FILELIST)

dependency_root="$work/dependency-root"
dependency_directory="$dependency_root/001-runtime/dependency"
consumer_directory="$dependency_root/005-utils/consumer"
module_shadow_directory="$dependency_root/modules/999-shadow/dependency"
module_only_directory="$dependency_root/modules/999-shadow/module-only"
module_consumer_directory="$dependency_root/005-utils/module-consumer"
mkdir -p \
    "$dependency_directory" \
    "$consumer_directory" \
    "$module_shadow_directory" \
    "$module_only_directory" \
    "$module_consumer_directory" \
    "$dependency_root/profiles"
cp "$ROOT/profiles/makepkg.conf" "$dependency_root/profiles/makepkg.conf"

cat > "$dependency_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=dependency
pkgver=1
depends=()
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    printf 'base\n' >> "$work/dependency-builds"
    install -Dm0644 /dev/null "\$develdir/usr/include/dependency.h"
}
package() { package_keep; }
recipe_main "\$@"
EOF
chmod 0755 "$dependency_directory/build.sh"

cat > "$module_shadow_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=dependency
pkgver=1
depends=()
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    printf 'module-shadow\n' >> "$work/module-dependency-builds"
    install -Dm0644 /dev/null "\$develdir/usr/include/dependency.h"
}
package() { package_keep; }
recipe_main "\$@"
EOF
chmod 0755 "$module_shadow_directory/build.sh"

cat > "$module_only_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=module-only
pkgver=1
depends=()
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    printf 'module-only\n' >> "$work/module-only-builds"
    install -Dm0644 /dev/null "\$develdir/usr/include/module-only.h"
}
package() { package_keep; }
recipe_main "\$@"
EOF
chmod 0755 "$module_only_directory/build.sh"

cat > "$consumer_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=consumer
pkgver=1
depends=(dependency)
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    [[ -f "\$EFILINUX_SYSROOT/usr/include/dependency.h" ]] || \
        die "dependency devel tree is absent from sysroot"
    install -Dm0644 /dev/null "\$develdir/usr/share/consumer"
}
package() { :; }
recipe_main "\$@"
EOF
chmod 0755 "$consumer_directory/build.sh"

EFILINUX_ROOT="$dependency_root" "$consumer_directory/build.sh"
[[ $(cat "$work/dependency-builds") == base ]] || {
    printf 'dependency lookup did not select the fixed base layer\n' >&2
    exit 1
}
[[ ! -e "$work/module-dependency-builds" ]] || {
    printf 'base dependency lookup executed a module recipe\n' >&2
    exit 1
}
rm -rf -- "$EFILINUX_SYSROOT"
mkdir -p "$EFILINUX_SYSROOT"
EFILINUX_ROOT="$dependency_root" "$consumer_directory/build.sh"
[[ -f "$EFILINUX_SYSROOT/usr/include/dependency.h" ]] || {
    printf 'cached consumer did not restore its dependency closure\n' >&2
    exit 1
}

cat > "$module_consumer_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=module-consumer
pkgver=1
depends=(module-only)
builddepends=()
makedepends=(install)
prepare() { :; }
build() { install -Dm0644 /dev/null "\$develdir/usr/share/module-consumer"; }
package() { :; }
recipe_main "\$@"
EOF
chmod 0755 "$module_consumer_directory/build.sh"
if EFILINUX_ROOT="$dependency_root" "$module_consumer_directory/build.sh" \
        >"$work/module-consumer.stdout" 2>"$work/module-consumer.stderr"; then
    printf 'base recipe accepted a dependency provided only by a module\n' >&2
    exit 1
fi
grep -Fq 'dependency recipe is missing: module-only' "$work/module-consumer.stderr"
[[ ! -e "$work/module-only-builds" ]] || {
    printf 'base dependency lookup executed a module-only recipe\n' >&2
    exit 1
}

diamond_root="$work/diamond-root"
shared_directory="$diamond_root/001-runtime/shared"
left_directory="$diamond_root/002-system/left"
right_directory="$diamond_root/003-graphical/right"
top_directory="$diamond_root/005-utils/top"
mkdir -p \
    "$shared_directory" \
    "$left_directory" \
    "$right_directory" \
    "$top_directory" \
    "$diamond_root/profiles"
cp "$ROOT/profiles/makepkg.conf" "$diamond_root/profiles/makepkg.conf"

cat > "$shared_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=shared
pkgver=1
depends=()
builddepends=()
makedepends=(install)
prepare() { :; }
recipe_cache_ready() {
    printf 'visit\n' >> "$work/shared-visits"
    return 0
}
build() { install -Dm0644 /dev/null "\$develdir/usr/include/shared.h"; }
package() { package_keep; }
recipe_main "\$@"
EOF
chmod 0755 "$shared_directory/build.sh"

for branch in left right; do
    case $branch in
        left) branch_directory=$left_directory ;;
        right) branch_directory=$right_directory ;;
    esac
    cat > "$branch_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=$branch
pkgver=1
depends=(shared)
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    [[ -f "\$EFILINUX_SYSROOT/usr/include/shared.h" ]] || \
        die "shared dependency is absent from sysroot"
    install -Dm0644 /dev/null "\$develdir/usr/include/$branch.h"
}
package() { package_keep; }
recipe_main "\$@"
EOF
    chmod 0755 "$branch_directory/build.sh"
done

cat > "$top_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"
pkgname=top
pkgver=1
depends=(left right)
builddepends=()
makedepends=(install)
prepare() { :; }
build() {
    [[ -f "\$EFILINUX_SYSROOT/usr/include/left.h" ]] || die "left dependency is absent"
    [[ -f "\$EFILINUX_SYSROOT/usr/include/right.h" ]] || die "right dependency is absent"
    install -Dm0644 /dev/null "\$develdir/usr/share/top"
}
package() { :; }
recipe_main "\$@"
EOF
chmod 0755 "$top_directory/build.sh"

rm -f "$work/shared-visits"
EFILINUX_ROOT="$diamond_root" "$top_directory/build.sh"
shared_visits=$(wc -l < "$work/shared-visits")
[[ "$shared_visits" == 1 ]] || {
    printf 'diamond dependency was processed %s times instead of once\n' "$shared_visits" >&2
    exit 1
}

shared_session_build="$work/shared-session-build"
shared_session_packages="$work/shared-session-packages"
shared_session_sysroot="$work/shared-session-sysroot"
shared_session_target="$work/shared-session-target"
shared_session="$shared_session_build/recipe-sessions/build"
mkdir -p "$shared_session"
rm -f "$work/shared-visits"
shared_session_environment=(
    EFILINUX_ROOT="$diamond_root"
    EFILINUX_BUILD="$shared_session_build"
    EFILINUX_PACKAGES="$shared_session_packages"
    EFILINUX_PACKAGE_INDEX="$shared_session_packages/index.tsv"
    EFILINUX_PACKAGE_WORK="$shared_session_build/packages"
    EFILINUX_SYSROOT="$shared_session_sysroot"
    EFILINUX_TARGET="$shared_session_target"
    EFILINUX_ROOTFS="$shared_session_target/rootfs"
    EFILINUX_STATE="$shared_session_build/state"
    EFILINUX_TEST="$shared_session_build/test"
    EFILINUX_LOGS="$shared_session_build/logs"
    EFILINUX_RECIPE_SESSION_DIR="$shared_session"
)
env "${shared_session_environment[@]}" "$left_directory/build.sh"
first_shared_session_visits=$(wc -l < "$work/shared-visits")
env "${shared_session_environment[@]}" "$right_directory/build.sh"
second_shared_session_visits=$(wc -l < "$work/shared-visits")
[[ "$first_shared_session_visits" == 1 && "$second_shared_session_visits" == 1 ]] || {
    printf 'shared build session repeated dependency resolution: %s then %s visits\n' \
        "$first_shared_session_visits" "$second_shared_session_visits" >&2
    exit 1
}

bad_directory="$work/bad"
mkdir -p "$bad_directory"
cat > "$bad_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"

pkgname=bad
pkgver=1.0

depends=()
builddepends=()
makedepends=(install)

prepare() { :; }
build() { install -Dm0644 /dev/null "\$develdir/usr/share/bad"; }
package() { chmod 0600 "\$pkgdir/usr/share/bad"; }
recipe_main "\$@"
EOF
chmod 0755 "$bad_directory/build.sh"

if "$bad_directory/build.sh" --no-deps >"$work/bad.stdout" 2>"$work/bad.stderr"; then
    printf 'package() metadata modification was accepted\n' >&2
    exit 1
fi
grep -Fq 'package() added or modified usr/share/bad' "$work/bad.stderr"

host_leak_directory="$work/host-leak"
mkdir -p "$host_leak_directory"
cat > "$host_leak_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"

pkgname=host-leak
pkgver=1
depends=()
builddepends=()
makedepends=(install)

prepare() { :; }
build() {
    install -Dm0644 /dev/null "\$develdir\$EFILINUX_BUILD/leaked-file"
}
package() { :; }
recipe_main "\$@"
EOF
chmod 0755 "$host_leak_directory/build.sh"

if "$host_leak_directory/build.sh" --no-deps \
        >"$work/host-leak.stdout" 2>"$work/host-leak.stderr"; then
    printf 'build-host path leak was accepted\n' >&2
    exit 1
fi
grep -Fq 'package tree contains build-host path:' "$work/host-leak.stderr"

library_directory="$work/library-family"
mkdir -p "$library_directory"
cat > "$library_directory/build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
source "\$ROOT/config.sh"
source "\$ROOT/lib/common.sh"
source "\$ROOT/lib/package.sh"
source "\$ROOT/lib/recipe.sh"

pkgname=library-family
pkgver=1
depends=()
builddepends=()
makedepends=(install ln)

prepare() { :; }
build() {
    install -Dm0644 /dev/null "\$develdir/usr/lib/libexample-1.so"
    ln -s libexample-1.so "\$develdir/usr/lib/libexample.so.1"
}
package() {
    local -a keep=()
    package_add_library_family keep 'libexample.so.1*'
    package_keep "\${keep[@]}"
}
recipe_main "\$@"
EOF
chmod 0755 "$library_directory/build.sh"
"$library_directory/build.sh" --no-deps
library_archive=$(awk -F '\t' '$1 == "library-family" { print $5 }' "$EFILINUX_PACKAGE_INDEX")
library_archive="$EFILINUX_PACKAGES/$library_archive"
grep -Fxq '/usr/lib/libexample.so.1' < <(tar -xOf "$library_archive" .INSTALL)
grep -Fxq '/usr/lib/libexample-1.so' < <(tar -xOf "$library_archive" .INSTALL)

"$ROOT/test/packages.sh"

printf 'recipe tests passed\n'
