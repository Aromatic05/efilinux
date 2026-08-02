#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
selector="$ROOT/000-kernel/linux-firmware/select_members.py"
materializer="$ROOT/000-kernel/linux-firmware/materialize_links.py"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

cat > "$work/include.list" <<'MANIFEST'
file direct.bin
file iwlwifi-exact-77.ucode
file iwlwifi-ty-a0-gf-a0-100.ucode
file iwlwifi-missing-100.ucode
file iwlwifi-blocked-100.ucode
file vendor/model-b/fw/main-5.bin
file vendor/model-c/fw/main-5.bin
file vendor/model-a/fw/alias.bin
file vendor/spaced.bin
versioned-fallback iwlwifi-
MANIFEST

cat > "$work/exclude.list" <<'MANIFEST'
file excluded.bin
file iwlwifi-blocked-89.ucode
MANIFEST

cat > "$work/WHENCE" <<'WHENCE'
Link: iwlwifi-exact-77.ucode -> intel/iwlwifi/iwlwifi-exact-77.ucode
Link: iwlwifi-ty-a0-gf-a0-89.ucode -> intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode
Link: iwlwifi-ty-a0-gf-a0-101.ucode -> intel/iwlwifi/iwlwifi-ty-a0-gf-a0-101.ucode
Link: vendor/model-b -> model-a
Link: vendor/model-c/fw -> ../model-a/fw
Link: vendor/model-a/fw/alias.bin -> main-5.bin
Link: vendor/spaced.bin  -> model-a/fw/main-5.bin
Link: vendor/absent.bin -> missing.bin
WHENCE

cat > "$work/archive.list" <<'MEMBERS'
linux-firmware-test/WHENCE
linux-firmware-test/direct.bin
linux-firmware-test/excluded.bin
linux-firmware-test/intel/iwlwifi/iwlwifi-exact-77.ucode
linux-firmware-test/intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode
linux-firmware-test/intel/iwlwifi/iwlwifi-ty-a0-gf-a0-101.ucode
linux-firmware-test/iwlwifi-blocked-89.ucode
linux-firmware-test/vendor/model-a/fw/main-5.bin
MEMBERS

python3 "$selector" \
    "$work/include.list" \
    "$work/exclude.list" \
    linux-firmware-test \
    "$work/WHENCE" \
    "$work/report.tsv" \
    < "$work/archive.list" > "$work/selected.list"

cat > "$work/expected.list" <<'EXPECTED'
linux-firmware-test/WHENCE
linux-firmware-test/direct.bin
linux-firmware-test/intel/iwlwifi/iwlwifi-exact-77.ucode
linux-firmware-test/intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode
linux-firmware-test/vendor/model-a/fw/main-5.bin
EXPECTED

cmp "$work/expected.list" "$work/selected.list"
grep -Fxq $'fallback\tiwlwifi-ty-a0-gf-a0-100.ucode\tiwlwifi-ty-a0-gf-a0-89.ucode' \
    "$work/report.tsv"
grep -Fxq $'unresolved\tiwlwifi-missing-100.ucode\t-' "$work/report.tsv"
grep -Fxq $'unresolved\tiwlwifi-blocked-100.ucode\t-' "$work/report.tsv"
grep -Fxq $'exact\tvendor/model-b/fw/main-5.bin\tvendor/model-b/fw/main-5.bin' \
    "$work/report.tsv"
grep -Fxq $'exact\tvendor/model-c/fw/main-5.bin\tvendor/model-c/fw/main-5.bin' \
    "$work/report.tsv"
grep -Fxq $'exact\tvendor/model-a/fw/alias.bin\tvendor/model-a/fw/alias.bin' \
    "$work/report.tsv"
grep -Fxq $'exact\tvendor/spaced.bin\tvendor/spaced.bin' "$work/report.tsv"

mkdir -p "$work/staging/intel/iwlwifi" "$work/staging/vendor/model-a/fw"
printf firmware > "$work/staging/intel/iwlwifi/iwlwifi-exact-77.ucode.zst"
printf firmware > "$work/staging/vendor/model-a/fw/main-5.bin.zst"
python3 "$materializer" "$work/WHENCE" "$work/staging"

test "$(readlink "$work/staging/iwlwifi-exact-77.ucode.zst")" = \
    intel/iwlwifi/iwlwifi-exact-77.ucode.zst
test "$(readlink "$work/staging/vendor/model-b")" = model-a
test -e "$work/staging/vendor/model-b/fw/main-5.bin.zst"
test "$(readlink "$work/staging/vendor/model-c/fw")" = ../model-a/fw
test -e "$work/staging/vendor/model-c/fw/main-5.bin.zst"
test "$(readlink "$work/staging/vendor/model-a/fw/alias.bin.zst")" = main-5.bin.zst
test -e "$work/staging/vendor/model-a/fw/alias.bin.zst"
test "$(readlink "$work/staging/vendor/spaced.bin.zst")" = model-a/fw/main-5.bin.zst
test -e "$work/staging/vendor/spaced.bin.zst"
test -z "$(find "$work/staging" -name '* *' -print -quit)"
test ! -e "$work/staging/vendor/absent.bin.zst"

printf 'firmware selection and WHENCE link materialization passed\n'
