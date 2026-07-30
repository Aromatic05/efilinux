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
makedepends=(grep install setcap setfacl)

prepare() {
    input_file "\$recipedir/payload.txt" "\$srcdir/payload.txt"
}

build() {
    install -Dm0644 "\$srcdir/payload.txt" "\$develdir/usr/share/mock/payload.txt"
    install -Dm0644 "\$srcdir/payload.txt" "\$develdir/usr/include/mock.h"
    install -Dm0755 "\$srcdir/payload.txt" "\$develdir/usr/bin/mock-cap"
}

check() {
    grep -Fxq 'runtime payload' "\$develdir/usr/share/mock/payload.txt"
    touch "\$recipework/check-ran"
}

devel() {
    chmod 0640 "\$develdir/usr/share/mock/payload.txt"
    setfacl -m user:1234:r-- "\$develdir/usr/share/mock/payload.txt"
    setcap cap_net_raw=ep "\$develdir/usr/bin/mock-cap"
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

dependency_root="$work/dependency-root"
dependency_directory="$dependency_root/stage/dependency"
consumer_directory="$dependency_root/stage/consumer"
mkdir -p "$dependency_directory" "$consumer_directory" "$dependency_root/config"
cp "$ROOT/config/makepkg.conf" "$dependency_root/config/makepkg.conf"

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
build() { install -Dm0644 /dev/null "\$develdir/usr/include/dependency.h"; }
package() { package_keep; }
recipe_main "\$@"
EOF
chmod 0755 "$dependency_directory/build.sh"

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
rm -rf -- "$EFILINUX_SYSROOT"
mkdir -p "$EFILINUX_SYSROOT"
EFILINUX_ROOT="$dependency_root" "$consumer_directory/build.sh"
[[ -f "$EFILINUX_SYSROOT/usr/include/dependency.h" ]] || {
    printf 'cached consumer did not restore its dependency closure\n' >&2
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

"$ROOT/test/packages.sh"

printf 'recipe tests passed\n'
