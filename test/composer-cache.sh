#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

export EFILINUX_ROOT="$ROOT"
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

source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/composer.sh"

ensure_directories
mkdir -p "$work/profile" "$work/archive-root" "$work/bin"
printf '%s\n' "$EFILINUX_PACKAGE_INDEX_HEADER" > "$EFILINUX_PACKAGE_INDEX"

create_package() {
    local name=$1
    shift
    local archive_root="$work/archive-root/$name"
    local archive="$EFILINUX_PACKAGES/$name.pkg.tar.zst"
    local dependency digest

    reset_directory "$archive_root"
    mkdir -p "$archive_root/devel/usr/share/$name"
    printf '%s\n' "$name" > "$archive_root/devel/usr/share/$name/payload"
    {
        printf 'format=%s\n' "$EFILINUX_PACKAGE_FORMAT"
        printf 'name=%s\n' "$name"
        printf 'version=1\n'
        printf 'arch=%s\n' "$EFILINUX_ARCH"
        printf 'x86_64_level=%s\n' "$EFILINUX_X86_64_LEVEL"
        printf 'recipe_key=key-%s\n' "$name"
        printf 'sysroot=true\n'
        for dependency in "$@"; do
            printf 'depends=%s\n' "$dependency"
        done
    } > "$archive_root/.PKGINFO"
    printf 'recipe=test/%s\n' "$name" > "$archive_root/.BUILDINFO"
    printf '/usr/share/%s/payload\n' "$name" > "$archive_root/.FILELIST"
    printf '/usr/share/%s/payload\n' "$name" > "$archive_root/.INSTALL"
    tar --create --use-compress-program='zstd --quiet' --file "$archive" \
        --directory "$archive_root" \
        .PKGINFO .BUILDINFO .FILELIST .INSTALL devel
    digest=$(sha256sum "$archive" | awk '{print $1}')
    printf '%s\t1\tkey-%s\t%s\t%s\t%s\n' \
        "$name" "$name" "$digest" "$(basename -- "$archive")" "$digest" \
        >> "$EFILINUX_PACKAGE_INDEX"
}

create_package base
create_package application base
{
    head -n 1 "$EFILINUX_PACKAGE_INDEX"
    tail -n +2 "$EFILINUX_PACKAGE_INDEX" | LC_ALL=C sort -t $'\t' -k1,1
} > "$EFILINUX_PACKAGE_INDEX.sorted"
mv "$EFILINUX_PACKAGE_INDEX.sorted" "$EFILINUX_PACKAGE_INDEX"
printf 'application\n' > "$work/profile/runtime.packages"

real_tar=$(command -v tar)
real_sha256sum=$(command -v sha256sum)
cat > "$work/bin/tar" <<'EOF_WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
    if [[ $argument == .PKGINFO ]]; then
        printf 'metadata-read\n' >> "$COMPOSER_METADATA_READS"
        break
    fi
done
exec "$COMPOSER_REAL_TAR" "$@"
EOF_WRAPPER
chmod 0755 "$work/bin/tar"
cat > "$work/bin/sha256sum" <<'EOF_WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
    if [[ $argument == *.pkg.tar.zst ]]; then
        printf 'archive-hash\n' >> "$COMPOSER_ARCHIVE_HASHES"
        break
    fi
done
exec "$COMPOSER_REAL_SHA256SUM" "$@"
EOF_WRAPPER
chmod 0755 "$work/bin/sha256sum"
export COMPOSER_REAL_TAR="$real_tar"
export COMPOSER_REAL_SHA256SUM="$real_sha256sum"
export COMPOSER_METADATA_READS="$work/metadata-reads"
export COMPOSER_ARCHIVE_HASHES="$work/archive-hashes"
export PATH="$work/bin:$PATH"

resolve_profile() {
    declare -gA COMPOSE_VISIT_STATE=()
    declare -gA COMPOSE_ARCHIVES=()
    declare -ga COMPOSE_ORDER=()
    compose_read_profile "$work/profile/runtime.packages"
    [[ "${COMPOSE_ORDER[*]}" == 'base application' ]] || {
        printf 'composer returned an unexpected package order: %s\n' "${COMPOSE_ORDER[*]}" >&2
        exit 1
    }
}

resolve_profile
first_reads=$(wc -l < "$COMPOSER_METADATA_READS")
((first_reads > 0)) || {
    printf 'initial dependency resolution did not inspect package metadata\n' >&2
    exit 1
}
first_hashes=$(wc -l < "$COMPOSER_ARCHIVE_HASHES")
resolve_profile
second_reads=$(wc -l < "$COMPOSER_METADATA_READS")
second_hashes=$(wc -l < "$COMPOSER_ARCHIVE_HASHES")
[[ "$second_reads" == "$first_reads" ]] || {
    printf 'cached dependency resolution reread package metadata: %s to %s reads\n' \
        "$first_reads" "$second_reads" >&2
    exit 1
}
[[ "$second_hashes" == "$first_hashes" ]] || {
    printf 'cached dependency resolution rehashed package archives: %s to %s hashes\n' \
        "$first_hashes" "$second_hashes" >&2
    exit 1
}

resolution_cache=$(compose_resolution_cache_path "$work/profile/runtime.packages")
printf 'damaged cache\n' > "$resolution_cache"
resolve_profile
uncached_reads=$(wc -l < "$COMPOSER_METADATA_READS")
third_hashes=$(wc -l < "$COMPOSER_ARCHIVE_HASHES")
((uncached_reads > second_reads)) || {
    printf 'damaged resolution cache did not fall back to dependency traversal\n' >&2
    exit 1
}
[[ "$third_hashes" == "$second_hashes" ]] || {
    printf 'verified package archives were hashed again: %s to %s hashes\n' \
        "$second_hashes" "$third_hashes" >&2
    exit 1
}

touch "$EFILINUX_PACKAGES/application.pkg.tar.zst"
rm -f -- "$resolution_cache"
resolve_profile
changed_archive_hashes=$(wc -l < "$COMPOSER_ARCHIVE_HASHES")
((changed_archive_hashes > third_hashes)) || {
    printf 'changed package archive did not invalidate verification cache\n' >&2
    exit 1
}

before_profile_change_reads=$(wc -l < "$COMPOSER_METADATA_READS")
printf '# profile revision\n' >> "$work/profile/runtime.packages"
resolve_profile
after_profile_change_reads=$(wc -l < "$COMPOSER_METADATA_READS")
after_profile_change_hashes=$(wc -l < "$COMPOSER_ARCHIVE_HASHES")
((after_profile_change_reads > before_profile_change_reads)) || {
    printf 'profile change did not invalidate dependency resolution cache\n' >&2
    exit 1
}
[[ "$after_profile_change_hashes" == "$changed_archive_hashes" ]] || {
    printf 'profile change unnecessarily rehashed verified package archives\n' >&2
    exit 1
}

printf 'composer dependency cache tests passed\n'
