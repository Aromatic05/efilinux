#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command awk grep readelf sed tar zstd
ensure_directories

rootfs="$EFILINUX_ROOTFS"
owners="$EFILINUX_ROOTFS_OWNERS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"
work="$EFILINUX_TEST/gnu-runtime"

[[ -x "$loader" ]] || die "target glibc loader is missing"
[[ -f "$owners" ]] || die "rootfs ownership manifest is missing"
reset_directory "$work"

target_elf() {
    "$loader" --library-path "$library_path" "$@"
}

assert_gnu_program() {
    local name=$1
    local owner=$2
    local path="$rootfs/usr/bin/$name"
    [[ -x "$path" ]] || die "GNU runtime command is missing: $name"
    if [[ -L "$path" && $(readlink -- "$path") == busybox ]]; then
        die "GNU runtime command still resolves to BusyBox: $name"
    fi
    awk -F '\t' -v path="/usr/bin/$name" -v owner="$owner" \
        '$1 == path && $3 == owner { found=1 } END { exit !found }' "$owners" ||
        die "GNU runtime command has the wrong package owner: $name"
}

assert_gnu_program bash bash
assert_gnu_program stat coreutils
assert_gnu_program readlink coreutils
assert_gnu_program realpath coreutils
assert_gnu_program find findutils
assert_gnu_program xargs findutils
assert_gnu_program grep grep
assert_gnu_program sed sed
assert_gnu_program gawk gawk
assert_gnu_program awk gawk
assert_gnu_program diff diffutils
assert_gnu_program tar tar
assert_gnu_program gzip gzip
assert_gnu_program cpio cpio
assert_gnu_program ps procps-ng
assert_gnu_program free procps-ng
assert_gnu_program top procps-ng

[[ -L "$rootfs/usr/bin/sh" ]] || die "/usr/bin/sh is not a symbolic link"
[[ $(readlink -- "$rootfs/usr/bin/sh") == busybox ]] || \
    die "/usr/bin/sh must remain the BusyBox rescue shell"
grep -Eq '^root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:/usr/bin/bash$' "$rootfs/etc/passwd" ||
    die "root login shell is not Bash"
grep -Fxq /usr/bin/bash "$rootfs/etc/shells" || die "Bash is missing from /etc/shells"

target_elf "$rootfs/usr/bin/bash" -c \
    'set -o pipefail; values=(alpha beta); [[ ${values[1]} == beta ]]'

touch "$work/stat-target"
target_elf "$rootfs/usr/bin/stat" -c '%s' "$work/stat-target" | grep -Fxq 0
ln -s stat-target "$work/stat-link"
target_elf "$rootfs/usr/bin/readlink" -f "$work/stat-link" | grep -Fxq "$work/stat-target"
mkdir -p "$work/find/a/b"
printf 'payload\n' > "$work/find/a/b/file"
target_elf "$rootfs/usr/bin/find" "$work/find" -mindepth 2 -print0 > "$work/find.out"
grep -aFq "$work/find/a/b" "$work/find.out"
printf 'alpha\nbeta\n' > "$work/text"
target_elf "$rootfs/usr/bin/grep" -E '^b.ta$' "$work/text" | grep -Fxq beta
target_elf "$rootfs/usr/bin/sed" -n '2p' "$work/text" | grep -Fxq beta
target_elf "$rootfs/usr/bin/gawk" 'END { print NR }' "$work/text" | grep -Fxq 2
cp "$work/text" "$work/text.copy"
target_elf "$rootfs/usr/bin/diff" -u "$work/text" "$work/text.copy" > /dev/null

target_elf "$rootfs/usr/bin/tar" -cf "$work/archive.tar" -C "$work" text
target_elf "$rootfs/usr/bin/tar" -tf "$work/archive.tar" | grep -Fxq text
target_elf "$rootfs/usr/bin/gzip" -c "$work/text" > "$work/text.gz"
target_elf "$rootfs/usr/bin/gzip" -dc "$work/text.gz" > "$work/text.gunzip"
cmp "$work/text" "$work/text.gunzip"
printf 'text\n' | (
    cd "$work"
    "$loader" --library-path "$library_path" "$rootfs/usr/bin/cpio" -o -H newc > archive.cpio
)
mkdir "$work/cpio-out"
(
    cd "$work/cpio-out"
    "$loader" --library-path "$library_path" "$rootfs/usr/bin/cpio" -id < ../archive.cpio
)
cmp "$work/text" "$work/cpio-out/text"
target_elf "$rootfs/usr/bin/ps" -e -o pid=,comm= > "$work/ps.out"
grep -Eq '[[:digit:]]+[[:space:]]+' "$work/ps.out"
target_elf "$rootfs/usr/bin/free" -b > "$work/free.out"
grep -Fq Mem: "$work/free.out"

package_payload_size() {
    local package=$1
    local list="$work/$package.list"
    awk -F '\t' -v package="$package" \
        '$3 == package && $2 != "directory" { sub(/^\//, "", $1); print $1 }' \
        "$owners" | LC_ALL=C sort -u > "$list"
    [[ -s "$list" ]] || die "rootfs contains no payload owned by $package"
    tar -C "$rootfs" -cf - -T "$list" | zstd -q -19 -c | wc -c
}

declare -A limits=(
    [bash]=450000
    [coreutils]=750000
    [findutils]=120000
    [grep]=80000
    [sed]=70000
    [gawk]=350000
    [diffutils]=110000
    [tar]=200000
    [gzip]=80000
    [cpio]=80000
    [procps-ng]=260000
)

total=0
for package in bash coreutils findutils grep sed gawk diffutils tar gzip cpio procps-ng; do
    size=$(package_payload_size "$package")
    printf '%-12s %8d bytes (limit %d)\n' "$package" "$size" "${limits[$package]}"
    (( size <= limits[$package] )) || die "$package runtime payload exceeds its size budget"
    total=$((total + size))
done
(( total <= 2400000 )) || die "GNU runtime payload exceeds the 2.4 MB aggregate budget"
printf 'GNU runtime payload total: %d bytes\n' "$total"

log "GNU runtime commands, semantics, login shell, and size budgets passed"
