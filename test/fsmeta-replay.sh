#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command chroot cp getcap getfacl grep unshare

[[ -d "$EFILINUX_ROOTFS" ]] || die "rootfs has not been composed"
[[ -x "$EFILINUX_ROOTFS/usr/bin/fsmeta-replay" ]] || \
    die "fsmeta-replay is missing from the rootfs"
[[ -f "$EFILINUX_ROOTFS/etc/filemeta/ownership.tsv" ]] || \
    die "file ownership metadata is missing from the rootfs"
[[ -f "$EFILINUX_ROOTFS/etc/filemeta/caps/iputils" ]] || \
    die "iputils capability metadata is missing from the rootfs"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
rootfs="$work/rootfs"
mkdir -p "$rootfs"
cp -a --reflink=auto "$EFILINUX_ROOTFS/." "$rootfs/"

run_replay() {
    unshare --user --map-root-user --mount --fork \
        chroot "$rootfs" /usr/bin/fsmeta-replay
}

expect_failure() {
    local description=$1

    if run_replay >"$work/stdout" 2>"$work/stderr"; then
        die "fsmeta-replay unexpectedly accepted $description"
    fi
    [[ -s "$work/stderr" ]] || \
        die "fsmeta-replay rejected $description without a diagnostic"
}

mkdir -p "$rootfs/etc/filemeta/acls"
cat > "$rootfs/etc/filemeta/acls/efilinux-system-config" <<'ACL'
EFILINUX-ACLS-1
/etc/issue	user::rw-,group::---,other::---
ACL

run_replay
run_replay
getcap -n "$rootfs/usr/bin/ping" | grep -Fq 'cap_net_raw=ep'
getcap -n "$rootfs/usr/bin/arping" | grep -Fq 'cap_net_raw=ep'
getfacl -cpn "$rootfs/etc/issue" | grep -Fxq 'user::rw-'
getfacl -cpn "$rootfs/etc/issue" | grep -Fxq 'group::---'
getfacl -cpn "$rootfs/etc/issue" | grep -Fxq 'other::---'

cat > "$rootfs/etc/filemeta/caps/bad-package" <<'CAP'
EFILINUX-CAPS-1
/etc/issue	cap_net_raw=ep
CAP
expect_failure "cross-package metadata"
rm -f "$rootfs/etc/filemeta/caps/bad-package"

cp "$rootfs/etc/filemeta/caps/iputils" "$work/iputils.caps"
cat > "$rootfs/etc/filemeta/caps/iputils" <<'CAP'
EFILINUX-CAPS-1
/usr/bin/ping
CAP
expect_failure "a malformed metadata record"
cp "$work/iputils.caps" "$rootfs/etc/filemeta/caps/iputils"

cat > "$rootfs/etc/filemeta/caps/base-files" <<'CAP'
EFILINUX-CAPS-1
/etc	cap_net_raw=ep
CAP
expect_failure "a capability on a directory"
rm -f "$rootfs/etc/filemeta/caps/base-files"

mv "$rootfs/usr/bin/ping" "$rootfs/usr/bin/ping.real"
ln -s /etc/passwd "$rootfs/usr/bin/ping"
expect_failure "a symbolic-link target"
rm -f "$rootfs/usr/bin/ping"
mv "$rootfs/usr/bin/ping.real" "$rootfs/usr/bin/ping"

mv "$rootfs/usr/bin/ping" "$rootfs/usr/bin/ping.real"
expect_failure "a missing target"
mv "$rootfs/usr/bin/ping.real" "$rootfs/usr/bin/ping"

mv "$rootfs/etc/filemeta/ownership.tsv" "$rootfs/etc/filemeta/ownership.saved"
ln -s ownership.saved "$rootfs/etc/filemeta/ownership.tsv"
expect_failure "a symbolic-link ownership table"
rm -f "$rootfs/etc/filemeta/ownership.tsv"
mv "$rootfs/etc/filemeta/ownership.saved" "$rootfs/etc/filemeta/ownership.tsv"

mv "$rootfs/etc/filemeta/acls" "$rootfs/etc/filemeta/acls.saved"
mv "$rootfs/etc/filemeta/caps" "$rootfs/etc/filemeta/caps.saved"
run_replay

log "ACL and capability replay, idempotence, and rejection gates passed"
