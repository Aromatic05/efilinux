#!/usr/bin/env bash

set -euo pipefail

readonly EFILINUX_RECIPE_API=1
readonly EFILINUX_MAKEPKG_CONF="$EFILINUX_ROOT/profiles/makepkg.conf"
readonly EFILINUX_RECIPE_FILE=$(readlink -f -- "${BASH_SOURCE[1]}")
readonly EFILINUX_RECIPE_LIB=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

RECIPE_INPUT_MODE=execute
RECIPE_PHASE=metadata
declare -ag RECIPE_INPUT_RECORDS=()
declare -ag RECIPE_DECLARED_CAPABILITIES=()
declare -ag RECIPE_DECLARED_ACLS=()

package_capability() {
    local path=$1
    local capability=$2

    [[ "$RECIPE_PHASE" == metadata ]] || \
        die "package_capability may only be declared at recipe scope"
    recipe_validate_target_path "$path"
    [[ -n $capability && $capability != *[$'\t\r\n']* ]] || \
        die "invalid capability declaration for $path"
    RECIPE_DECLARED_CAPABILITIES+=("$path"$'\t'"$capability")
}

package_acl() {
    local path=$1
    local acl=$2

    [[ "$RECIPE_PHASE" == metadata ]] || \
        die "package_acl may only be declared at recipe scope"
    recipe_validate_target_path "$path"
    [[ -n $acl && $acl != *[$'\t\r\n']* ]] || \
        die "invalid ACL declaration for $path"
    RECIPE_DECLARED_ACLS+=("$path"$'\t'"$acl")
}

recipe_relative_path() {
    local base=$1
    local path=$2
    local description=$3
    local canonical_base canonical_path

    canonical_base=$(realpath -m -- "$base")
    canonical_path=$(realpath -m -- "$path")
    case $canonical_path in
        "$canonical_base"/*)
            printf '%s' "${canonical_path#"$canonical_base/"}"
            ;;
        *)
            die "$description must be inside $canonical_base: $path"
            ;;
    esac
}

download() {
    local url=$1
    local output=$2
    local relative_output

    relative_output=$(recipe_relative_path "$downloaddir" "$output" "download output")
    RECIPE_INPUT_RECORDS+=("download=$url|$relative_output")
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    require_command curl
    mkdir -p "$(dirname -- "$output")"
    download_file "$url" "$output"
}

checksum() {
    local algorithm=$1
    local expected=$2
    local file=$3
    local relative_file

    case $algorithm in
        md5|sha256) ;;
        *) die "unsupported checksum algorithm: $algorithm" ;;
    esac
    relative_file=$(recipe_relative_path "$downloaddir" "$file" "checksum input")
    RECIPE_INPUT_RECORDS+=("checksum=$algorithm|$expected|$relative_file")
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    case $algorithm in
        md5)
            require_command md5sum
            verify_md5 "$expected" "$file"
            ;;
        sha256)
            require_command sha256sum
            verify_sha256 "$expected" "$file"
            ;;
    esac
}

extract() {
    local archive=$1
    local destination=$2

    recipe_relative_path "$downloaddir" "$archive" "archive input" >/dev/null
    recipe_relative_path "$srcdir" "$destination" "extract destination" >/dev/null

    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    require_command tar
    extract_source "$archive" "$destination"
}

extract_contents() {
    local archive=$1
    local destination=$2

    recipe_relative_path "$downloaddir" "$archive" "archive input" >/dev/null
    recipe_relative_path "$srcdir" "$destination" "extract destination" >/dev/null

    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    require_command tar
    reset_directory "$destination"
    tar --extract --file "$archive" --directory "$destination"
}

extract_zip() {
    local archive=$1
    local destination=$2
    local root_directory=$3
    local temporary

    recipe_relative_path "$downloaddir" "$archive" "archive input" >/dev/null
    recipe_relative_path "$srcdir" "$destination" "extract destination" >/dev/null
    [[ -n $root_directory && $root_directory != /* && $root_directory != *..* ]] || \
        die "invalid zip root directory: $root_directory"

    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    require_command unzip
    temporary="$recipework/unzip"
    reset_directory "$temporary"
    unzip -q "$archive" -d "$temporary"
    [[ -d "$temporary/$root_directory" ]] || \
        die "zip root directory is missing: $root_directory"
    reset_directory "$destination"
    cp -a "$temporary/$root_directory/." "$destination/"
    rm -rf -- "$temporary"
}

input_file() {
    local source=$1
    local destination=$2
    local digest relative_source relative_destination

    [[ -f "$source" ]] || die "recipe input file is missing: $source"
    relative_source=$(recipe_relative_path "$recipedir" "$source" "recipe input file")
    relative_destination=$(recipe_relative_path "$srcdir" "$destination" "recipe input destination")
    digest=$(sha256sum "$source" | awk '{print $1}')
    RECIPE_INPUT_RECORDS+=("input-file=$relative_source|$digest|$relative_destination")
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    mkdir -p "$(dirname -- "$destination")"
    cp -a -- "$source" "$destination"
}

input_shared_file() {
    local source=$1
    local destination=$2
    local digest relative_source relative_destination

    [[ -f "$source" ]] || die "shared recipe input file is missing: $source"
    relative_source=$(recipe_relative_path "$EFILINUX_ROOT" "$source" "shared recipe input file")
    relative_destination=$(recipe_relative_path "$srcdir" "$destination" "recipe input destination")
    digest=$(sha256sum "$source" | awk '{print $1}')
    RECIPE_INPUT_RECORDS+=("input-shared-file=$relative_source|$digest|$relative_destination")
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    mkdir -p "$(dirname -- "$destination")"
    cp -a -- "$source" "$destination"
}

input_tree() {
    local source=$1
    local destination=$2
    local digest relative_source relative_destination

    [[ -d "$source" ]] || die "recipe input tree is missing: $source"
    relative_source=$(recipe_relative_path "$recipedir" "$source" "recipe input tree")
    relative_destination=$(recipe_relative_path "$srcdir" "$destination" "recipe input destination")
    digest=$(tar --create --file - --sort=name --mtime='@0' \
        --owner=0 --group=0 --numeric-owner --directory "$source" . | \
        sha256sum | awk '{print $1}')
    RECIPE_INPUT_RECORDS+=("input-tree=$relative_source|$digest|$relative_destination")
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    mkdir -p "$destination"
    cp -a -- "$source/." "$destination/"
}

cargo_vendor() {
    local manifest=$1
    local vendor_directory=$2
    local manifest_relative vendor_relative cargo_home

    manifest_relative=$(recipe_relative_path "$srcdir" "$manifest" "Cargo manifest")
    vendor_relative=$(recipe_relative_path "$srcdir" "$vendor_directory" "Cargo vendor directory")
    RECIPE_INPUT_RECORDS+=("cargo-vendor=$manifest_relative|$vendor_relative")
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    [[ -f "$manifest" ]] || die "Cargo manifest is missing: $manifest"
    [[ -f "$(dirname -- "$manifest")/Cargo.lock" ]] || \
        die "Cargo.lock is missing beside $manifest"
    cargo_home="$recipework/cargo-home"
    reset_directory "$cargo_home"
    reset_directory "$vendor_directory"
    CARGO_HOME="$cargo_home" cargo vendor \
        --locked \
        --manifest-path "$manifest" \
        "$vendor_directory" > "$cargo_home/config.toml"
}

target_pkg_config() {
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        pkg-config "$@"
}

target_env() {
    env \
        CC="$CC" \
        CXX="$CXX" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$@"
}

strip_all() {
    local root path
    local -a paths=()

    [[ "$RECIPE_PHASE" == devel ]] || die "strip_all may only be used from devel()"
    require_command "$READELF" "$STRIP"
    for root in "$@"; do
        [[ -e "$root" || -L "$root" ]] || die "strip path is missing: $root"
        paths=()
        if [[ -f "$root" && ! -L "$root" ]]; then
            paths=("$root")
        else
            mapfile -d '' -t paths < <(find "$root" -type f -print0)
        fi
        for path in "${paths[@]}"; do
            case $path in
                *.a|*.o|*.lo|*.bc|*.ko|*.ko.*|*/lib/modules/*) continue ;;
            esac
            if "$READELF" --file-header "$path" >/dev/null 2>&1; then
                "$STRIP" --strip-unneeded "$path"
            fi
        done
    done
}

package_keep() {
    local requested path base entry relative keep
    local -a exact_paths=()
    local -a tree_paths=()

    [[ "$RECIPE_PHASE" == package ]] || die "package_keep may only be used from package()"
    for requested in "$@"; do
        recipe_validate_target_path "${requested%/}"
        base=${requested%/}
        [[ -e "$pkgdir$base" || -L "$pkgdir$base" ]] || \
            die "package_keep path is missing from devel tree: $base"
        if [[ $requested == */ ]]; then
            [[ -d "$pkgdir$base" && ! -L "$pkgdir$base" ]] || \
                die "package_keep tree is not a directory: $base"
            tree_paths+=("$base")
        else
            exact_paths+=("$base")
        fi
    done

    for path in \
        "/etc/filemeta/acls/$pkgname" \
        "/etc/filemeta/caps/$pkgname"; do
        if [[ -f "$pkgdir$path" ]]; then
            exact_paths+=("$path")
        fi
    done

    while IFS= read -r -d '' entry; do
        relative=/${entry#"$pkgdir/"}
        keep=false
        for path in "${exact_paths[@]}"; do
            if [[ "$relative" == "$path" || "$path" == "$relative/"* ]]; then
                keep=true
                break
            fi
        done
        if [[ "$keep" == false ]]; then
            for path in "${tree_paths[@]}"; do
                if [[ "$relative" == "$path" || "$relative" == "$path/"* || "$path" == "$relative/"* ]]; then
                    keep=true
                    break
                fi
            done
        fi
        if [[ "$keep" == false ]]; then
            rm -rf -- "$entry"
        fi
    done < <(find "$pkgdir" -mindepth 1 -depth -print0 | LC_ALL=C sort -z)
}

package_add_library_family() {
    local output_name=$1
    local pattern=$2
    local library relative link_target target
    local -a matches=() pending=()
    local -A seen=()
    local -n output=$output_name

    [[ "$RECIPE_PHASE" == package ]] || \
        die "package_add_library_family may only be used from package()"
    [[ $pattern != */* && -n $pattern ]] || \
        die "invalid library family pattern: $pattern"

    mapfile -d '' -t matches < <(
        find "$pkgdir/usr/lib" -maxdepth 1 \
            \( -type f -o -type l \) \
            -name "$pattern" \
            -print0 | LC_ALL=C sort -z
    )
    ((${#matches[@]} > 0)) || die "runtime library family is missing: $pattern"
    pending=("${matches[@]}")
    while ((${#pending[@]})); do
        library=${pending[0]}
        pending=("${pending[@]:1}")
        [[ -z ${seen[$library]+x} ]] || continue
        seen[$library]=1
        relative=/${library#"$pkgdir/"}
        output+=("$relative")
        [[ -L "$library" ]] || continue

        link_target=$(readlink -- "$library")
        if [[ $link_target == /* ]]; then
            target=$(realpath -m -s -- "$pkgdir$link_target")
        else
            target=$(realpath -m -s -- "$(dirname -- "$library")/$link_target")
        fi
        case $target in
            "$pkgdir"/*) ;;
            *) die "runtime library link escapes devel tree: $relative -> $link_target" ;;
        esac
        [[ -e "$target" || -L "$target" ]] || \
            die "runtime library link target is missing: $relative -> $link_target"
        pending+=("$target")
    done
}

recipe_validate_target_path() {
    local path=$1

    [[ $path == /* ]] || die "target path must be absolute: $path"
    [[ $path != / && $path != *//* && $path != */../* && $path != */.. && $path != *[$'\t\r\n']* ]] || \
        die "invalid target path: $path"
}

recipe_append_generated_filemeta() {
    local kind=$1
    local header=$2
    local path=$3
    local value=$4
    local metadata="$develdir/etc/filemeta/$kind/$pkgname"

    recipe_validate_target_path "$path"
    [[ -n $value && $value != *[$'\t\r\n']* ]] || \
        die "invalid generated $kind metadata for $path"
    if [[ ! -e "$metadata" ]]; then
        install -Dm0644 /dev/null "$metadata"
        printf '%s\n' "$header" > "$metadata"
    fi
    printf '%s\t%s\n' "$path" "$value" >> "$metadata"
}

recipe_generate_filemeta() {
    local entry relative capability acl existing record path value extra target

    if [[ -d "$develdir/etc/filemeta" ]]; then
        existing=$(find "$develdir/etc/filemeta" -mindepth 1 -print -quit)
        [[ -z "$existing" ]] || \
            die "reserved /etc/filemeta content must not be installed by build() or devel(): ${existing#"$develdir"}"
    fi

    for record in "${RECIPE_DECLARED_CAPABILITIES[@]}"; do
        IFS=$'\t' read -r path value extra <<<"$record"
        [[ -n "$path" && -n "$value" && -z ${extra:-} ]] || \
            die "malformed declared capability for $pkgname"
        target="$develdir$path"
        [[ -f "$target" && ! -L "$target" ]] || \
            die "declared capability target is not a regular file: $path"
        recipe_append_generated_filemeta caps EFILINUX-CAPS-1 "$path" "$value"
    done

    for record in "${RECIPE_DECLARED_ACLS[@]}"; do
        IFS=$'\t' read -r path value extra <<<"$record"
        [[ -n "$path" && -n "$value" && -z ${extra:-} ]] || \
            die "malformed declared ACL for $pkgname"
        target="$develdir$path"
        [[ -e "$target" && ! -L "$target" ]] || \
            die "declared ACL target is missing or symbolic: $path"
        recipe_append_generated_filemeta acls EFILINUX-ACLS-1 "$path" "$value"
    done

    while IFS= read -r -d '' entry; do
        capability=$(getcap -n "$entry" 2>/dev/null || true)
        [[ -n "$capability" ]] || continue
        [[ "$capability" == "$entry "* ]] || \
            die "cannot parse capability metadata for ${entry#"$develdir"}"
        capability=${capability#"$entry "}
        relative=/${entry#"$develdir/"}
        recipe_append_generated_filemeta caps EFILINUX-CAPS-1 "$relative" "$capability"
    done < <(find "$develdir" -type f -print0 | LC_ALL=C sort -z)

    while IFS= read -r -d '' entry; do
        [[ ! -L "$entry" ]] || continue
        acl=$(getfacl -cpnEs -- "$entry" 2>/dev/null || true)
        [[ -n "$acl" ]] || continue
        acl=$(printf '%s\n' "$acl" | sed '/^$/d' | paste -sd, -)
        [[ -n "$acl" ]] || continue
        relative=/${entry#"$develdir/"}
        recipe_append_generated_filemeta acls EFILINUX-ACLS-1 "$relative" "$acl"
    done < <(find "$develdir" -mindepth 1 -print0 | LC_ALL=C sort -z)
}

recipe_normalize_filemeta() {
    local kind header actual_header metadata temporary

    for kind in acls caps; do
        metadata="$develdir/etc/filemeta/$kind/$pkgname"
        [[ -f "$metadata" ]] || continue
        case $kind in
            acls) header=EFILINUX-ACLS-1 ;;
            caps) header=EFILINUX-CAPS-1 ;;
        esac
        IFS= read -r actual_header < "$metadata"
        [[ "$actual_header" == "$header" ]] || die "invalid $kind metadata header for $pkgname"
        temporary="$metadata.tmp"
        {
            printf '%s\n' "$header"
            tail -n +2 "$metadata" | LC_ALL=C sort -u
        } > "$temporary"
        awk -F '\t' '
            NR == 1 { next }
            seen[$1] && seen[$1] != $2 { exit 1 }
            { seen[$1] = $2 }
        ' "$temporary" || die "conflicting $kind declarations for $pkgname"
        mv -- "$temporary" "$metadata"
    done
}

recipe_validate_filemeta_subset() {
    local kind header metadata package_metadata line path value extra target relative

    if [[ -d "$develdir/etc/filemeta" ]]; then
        while IFS= read -r -d '' metadata; do
            relative=${metadata#"$develdir/etc/filemeta/"}
            case $relative in
                "acls/$pkgname"|"caps/$pkgname") ;;
                *) die "package contains undeclared file metadata path: /etc/filemeta/$relative" ;;
            esac
        done < <(find "$develdir/etc/filemeta" -type f -print0)
    fi

    for kind in acls caps; do
        metadata="$develdir/etc/filemeta/$kind/$pkgname"
        [[ -f "$metadata" ]] || continue
        package_metadata="$pkgdir/etc/filemeta/$kind/$pkgname"
        [[ -f "$package_metadata" ]] || die "package() removed $kind metadata for $pkgname"
        case $kind in
            acls) header=EFILINUX-ACLS-1 ;;
            caps) header=EFILINUX-CAPS-1 ;;
        esac
        IFS= read -r line < "$metadata"
        [[ "$line" == "$header" ]] || die "invalid $kind metadata header for $pkgname"
        while IFS=$'\t' read -r path value extra; do
            [[ -n "$path" ]] || continue
            [[ -n "$value" && -z ${extra:-} ]] || die "malformed $kind metadata for $pkgname"
            recipe_validate_target_path "$path"
            target="$pkgdir$path"
            [[ -e "$target" && ! -L "$target" ]] || \
                die "package() removed or replaced $kind target: $path"
            [[ "$kind" != caps || -f "$target" ]] || \
                die "capability target is not a regular file: $path"
        done < <(tail -n +2 "$metadata")
    done
}

recipe_json_quote() {
    local value=$1

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '"%s"' "$value"
}

recipe_json_array() {
    local first=true value

    printf '['
    for value in "$@"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        recipe_json_quote "$value"
    done
    printf ']'
}

recipe_validate_metadata() {
    sysroot=${sysroot:-true}
    [[ ${pkgname+x} ]] || die "recipe does not define pkgname"
    [[ ${pkgver+x} ]] || die "recipe does not define pkgver"
    [[ $pkgname =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || die "invalid pkgname: $pkgname"
    [[ -n $pkgver && $pkgver != */* && $pkgver != *[$'\t\r\n ']* ]] || \
        die "invalid pkgver: $pkgver"
    [[ $(basename -- "$recipedir") == "$pkgname" ]] || \
        die "recipe directory name must match pkgname: $recipedir"

    declare -p depends >/dev/null 2>&1 || die "recipe does not define depends as an array"
    declare -p builddepends >/dev/null 2>&1 || die "recipe does not define builddepends as an array"
    declare -p makedepends >/dev/null 2>&1 || die "recipe does not define makedepends as an array"
    [[ $(declare -p depends) == 'declare -a'* ]] || die "depends must be an indexed array"
    [[ $(declare -p builddepends) == 'declare -a'* ]] || die "builddepends must be an indexed array"
    [[ $(declare -p makedepends) == 'declare -a'* ]] || die "makedepends must be an indexed array"
    [[ "$sysroot" == true || "$sysroot" == false ]] || \
        die "sysroot must be true or false: $sysroot"

    declare -F prepare >/dev/null || die "recipe does not define prepare()"
    declare -F build >/dev/null || die "recipe does not define build()"
    declare -F package >/dev/null || die "recipe does not define package()"
}

recipe_initialize_paths() {
    recipefile=$EFILINUX_RECIPE_FILE
    recipedir=$(dirname -- "$recipefile")
    recipework="$EFILINUX_BUILD/recipes/$pkgname-$pkgver"
    srcdir="$recipework/src"
    builddir="$recipework/build"
    develdir="$recipework/devel"
    pkgdir="$recipework/package"
    downloaddir="$EFILINUX_DOWNLOADS"
    recipe_source_records="$recipework/sources.list"
    export recipefile recipedir recipework srcdir builddir develdir pkgdir downloaddir
}

recipe_collect_inputs() {
    RECIPE_INPUT_RECORDS=()
    RECIPE_INPUT_MODE=metadata
    prepare
    RECIPE_INPUT_MODE=execute
}

recipe_write_source_records() {
    local record

    mkdir -p "$(dirname -- "$recipe_source_records")"
    : > "$recipe_source_records"
    for record in "${RECIPE_INPUT_RECORDS[@]}"; do
        printf 'source=%s\n' "$record" >> "$recipe_source_records"
    done
}

recipe_verify_source_records() {
    local actual="$recipework/sources.actual"
    local record

    : > "$actual"
    for record in "${RECIPE_INPUT_RECORDS[@]}"; do
        printf 'source=%s\n' "$record" >> "$actual"
    done
    cmp -s "$recipe_source_records" "$actual" || \
        die "prepare() declared different inputs during execution and metadata collection"
}

recipe_compute_key() {
    {
        printf 'recipe_api=%s\n' "$EFILINUX_RECIPE_API"
        printf 'package_format=%s\n' "$EFILINUX_PACKAGE_FORMAT"
        printf 'name=%s\n' "$pkgname"
        printf 'version=%s\n' "$pkgver"
        printf 'arch=%s\n' "$EFILINUX_ARCH"
        printf 'x86_64_level=%s\n' "$EFILINUX_X86_64_LEVEL"
        sha256sum "$recipefile"
        sha256sum "$EFILINUX_MAKEPKG_CONF"
        printf '%s\n' "${RECIPE_INPUT_RECORDS[@]}"
    } | sha256sum | awk '{print $1}'
}

recipe_print_metadata() {
    local recipe_key

    recipe_collect_inputs
    recipe_key=$(recipe_compute_key)
    printf '{'
    printf '"pkgname":'; recipe_json_quote "$pkgname"
    printf ',"pkgver":'; recipe_json_quote "$pkgver"
    printf ',"depends":'; recipe_json_array "${depends[@]}"
    printf ',"builddepends":'; recipe_json_array "${builddepends[@]}"
    printf ',"makedepends":'; recipe_json_array "${makedepends[@]}"
    printf ',"sysroot":%s' "$sysroot"
    printf ',"capabilities":'; recipe_json_array "${RECIPE_DECLARED_CAPABILITIES[@]}"
    printf ',"acls":'; recipe_json_array "${RECIPE_DECLARED_ACLS[@]}"
    printf ',"sources":'; recipe_json_array "${RECIPE_INPUT_RECORDS[@]}"
    printf ',"recipe_key":'; recipe_json_quote "$recipe_key"
    printf '}\n'
}

recipe_find_dependency() {
    local dependency=$1
    local layer candidate found=
    local -a layers=(
        000-kernel
        001-runtime
        002-system
        003-graphical
        004-desktop
        005-utils
        005-applications
    )

    for layer in "${layers[@]}"; do
        candidate="$EFILINUX_ROOT/$layer/$dependency/build.sh"
        [[ -f "$candidate" ]] || continue
        if [[ -n "$found" ]]; then
            die "multiple recipe directories provide $dependency"
        fi
        found=$candidate
    done
    [[ -n "$found" ]] || die "dependency recipe is missing: $dependency"
    printf '%s' "$found"
}

recipe_session_cleanup() {
    [[ ${RECIPE_SESSION_OWNER:-false} == true ]] || return
    rm -rf -- "$EFILINUX_RECIPE_SESSION_DIR"
}

recipe_session_initialize() {
    RECIPE_SESSION_OWNER=false
    if [[ -n ${EFILINUX_RECIPE_SESSION_DIR:-} ]]; then
        return
    fi

    mkdir -p "$EFILINUX_BUILD/recipe-sessions"
    EFILINUX_RECIPE_SESSION_DIR="$EFILINUX_BUILD/recipe-sessions/$$-$RANDOM"
    (umask 077; mkdir "$EFILINUX_RECIPE_SESSION_DIR")
    export EFILINUX_RECIPE_SESSION_DIR
    RECIPE_SESSION_OWNER=true
    trap recipe_session_cleanup EXIT
}

recipe_session_is_done() {
    [[ -f "$EFILINUX_RECIPE_SESSION_DIR/done/$pkgname" ]]
}

recipe_session_mark_done() {
    mkdir -p "$EFILINUX_RECIPE_SESSION_DIR/done"
    : > "$EFILINUX_RECIPE_SESSION_DIR/done/$pkgname"
}

recipe_build_dependencies() {
    local dependency producer stack=${EFILINUX_RECIPE_STACK:-:}

    [[ $stack != *":$pkgname:"* ]] || die "dependency cycle detected at $pkgname"
    export EFILINUX_RECIPE_STACK="$stack$pkgname:"
    for dependency in "${depends[@]}" "${builddepends[@]}"; do
        [[ -n "$dependency" ]] || continue
        producer=$(recipe_find_dependency "$dependency")
        "$producer"
    done
}

recipe_require_host_tools() {
    require_command awk cmp cp fakeroot find getcap getfacl grep install paste python3 readlink realpath sed sha256sum sort stat tail tar xargs zstd
    ((${#makedepends[@]} == 0)) || require_command "${makedepends[@]}"
}

recipe_sanitize_environment() {
    unset ACLOCAL_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH CMAKE_PREFIX_PATH CPATH
    unset DYLD_LIBRARY_PATH LIBRARY_PATH PERL5LIB PKG_CONFIG_PATH
    unset PYTHONPATH RUSTFLAGS
    unset AR AS CC CFLAGS CPPFLAGS CXX CXXFLAGS LD LDFLAGS MAKEFLAGS NM
    unset OBJCOPY OBJDUMP RANLIB READELF STRIP
    if [[ -z ${FAKEROOTKEY:-} ]]; then
        unset LD_LIBRARY_PATH
    fi
}

recipe_tree_manifest() {
    local directory=$1
    local output=$2

    python3 "$EFILINUX_RECIPE_LIB/tree-manifest.py" "$directory" "$output"
    recipe_validate_manifest_paths "$output"
}

recipe_validate_manifest_paths() {
    local manifest=$1
    local host_path target_prefix leaked_path
    local -a forbidden_paths=(
        "${EFILINUX_BUILD:-}"
        "${EFILINUX_DOWNLOADS:-}"
        "${EFILINUX_PACKAGES:-}"
        "${EFILINUX_ROOT:-}"
        "${EFILINUX_SYSROOT:-}"
        "${EFILINUX_TARGET:-}"
    )

    for host_path in "${forbidden_paths[@]}"; do
        [[ $host_path == /* && $host_path != / ]] || continue
        target_prefix=${host_path#/}
        leaked_path=$(awk -F '\t' -v prefix="$target_prefix" \
            '$1 == prefix || index($1, prefix "/") == 1 { print "/" $1; exit }' \
            "$manifest")
        [[ -z $leaked_path ]] || \
            die "package tree contains build-host path: $leaked_path"
    done
}

recipe_verify_package_subset() {
    local before_manifest=$1
    local devel_after="$recipework/devel.after"
    local package_manifest="$recipework/package.manifest"
    local subset_missing="$recipework/package.subset-missing"
    local record relative expected

    recipe_tree_manifest "$develdir" "$devel_after"
    cmp -s "$before_manifest" "$devel_after" || \
        die "package() modified the devel tree"
    recipe_tree_manifest "$pkgdir" "$package_manifest"

    LC_ALL=C comm -23 "$package_manifest" "$before_manifest" > "$subset_missing"
    if [[ -s "$subset_missing" ]]; then
        IFS= read -r record < "$subset_missing"
        relative=${record%%$'\t'*}
        expected=$(awk -F '\t' -v path="$relative" '$1 == path { print; exit }' "$before_manifest")
        die "package() added or modified $relative (expected: ${expected:-missing}; actual: $record)"
    fi
}

recipe_run_internal_build() {
    local recipe_key=$1
    local skip_check=$2
    local devel_before="$recipework/devel.before"

    recipe_require_host_tools
    recipe_sanitize_environment
    source "$EFILINUX_MAKEPKG_CONF"
    reset_directory "$develdir"
    reset_directory "$pkgdir"

    RECIPE_PHASE=build
    log "Building $pkgname $pkgver"
    build
    if declare -F check >/dev/null && [[ "$skip_check" != true ]]; then
        RECIPE_PHASE=check
        log "Checking $pkgname $pkgver"
        check
    fi
    if declare -F devel >/dev/null; then
        RECIPE_PHASE=devel
        log "Preparing devel tree for $pkgname $pkgver"
        devel
    fi
    recipe_generate_filemeta
    recipe_normalize_filemeta

    recipe_tree_manifest "$develdir" "$devel_before"
    package_clone_tree "$develdir" "$pkgdir"
    RECIPE_PHASE=package
    log "Preparing install subset for $pkgname $pkgver"
    package
    recipe_verify_package_subset "$devel_before"
    recipe_validate_filemeta_subset

    package_create_archive \
        "$pkgname" "$pkgver" "$recipe_key" \
        "$develdir" "$pkgdir" "$recipefile" "$recipe_source_records"
    if [[ "$sysroot" == true ]]; then
        package_merge_devel_into_sysroot "$develdir"
    fi
    rm -rf -- "$srcdir" "$builddir" "$develdir" "$pkgdir"
}

recipe_run_internal_repackage() {
    local recipe_key=$1
    local source_archive=$2
    local devel_before="$recipework/devel.before"

    recipe_require_host_tools
    recipe_sanitize_environment
    source "$EFILINUX_MAKEPKG_CONF"
    reset_directory "$develdir"
    reset_directory "$pkgdir"
    package_extract_devel "$source_archive" "$develdir"

    recipe_tree_manifest "$develdir" "$devel_before"
    package_clone_tree "$develdir" "$pkgdir"
    RECIPE_PHASE=package
    log "Repackaging install subset for $pkgname $pkgver"
    package
    recipe_verify_package_subset "$devel_before"
    recipe_validate_filemeta_subset

    package_create_archive \
        "$pkgname" "$pkgver" "$recipe_key" \
        "$develdir" "$pkgdir" "$recipefile" "$recipe_source_records"
    if [[ "$sysroot" == true ]]; then
        package_merge_devel_into_sysroot "$develdir"
    fi
    rm -rf -- "$develdir" "$pkgdir"
}

recipe_repackage() {
    local recipe_key archive archive_version

    recipe_require_host_tools
    recipe_collect_inputs
    recipe_key=$(recipe_compute_key)
    archive=$(package_current_archive "$pkgname")
    archive_version=$(tar --extract --to-stdout --file "$archive" .PKGINFO | \
        sed -n 's/^version=//p')
    [[ "$archive_version" == "$pkgver" ]] || \
        die "cannot repackage $pkgname $pkgver from indexed version $archive_version"
    recipe_write_source_records

    fakeroot -- "$recipefile" --internal-repackage "$recipe_key" "$archive"
}

recipe_run() {
    local force=$1
    local skip_check=$2
    local no_dependencies=$3
    local recipe_key

    if [[ "$force" != true ]] && recipe_session_is_done; then
        return
    fi

    recipe_require_host_tools
    recipe_collect_inputs
    recipe_key=$(recipe_compute_key)

    if [[ "$no_dependencies" != true ]]; then
        recipe_build_dependencies
    fi

    if [[ "$force" != true ]]; then
        if declare -F recipe_cache_ready >/dev/null && \
           ! recipe_cache_ready "$recipe_key"; then
            log "Package cache for $pkgname requires missing local build state"
        elif package_restore_recipe_cache \
                "$pkgname" "$pkgver" "$recipe_key" "$sysroot"; then
            recipe_session_mark_done
            return
        fi
    fi

    reset_directory "$srcdir"
    reset_directory "$builddir"
    reset_directory "$develdir"
    reset_directory "$pkgdir"
    recipe_write_source_records
    RECIPE_INPUT_RECORDS=()
    RECIPE_INPUT_MODE=execute
    prepare
    recipe_verify_source_records

    fakeroot -- "$recipefile" --internal-build "$recipe_key" "$skip_check"
    recipe_session_mark_done
}

recipe_main() {
    local force=false skip_check=false no_dependencies=false repackage=false

    recipe_initialize_paths
    recipe_validate_metadata

    case ${1:-} in
        --print-name)
            printf '%s\n' "$pkgname"
            return
            ;;
        --print-metadata)
            recipe_print_metadata
            return
            ;;
        --internal-build)
            [[ $# -eq 3 ]] || die "invalid internal recipe invocation"
            recipe_run_internal_build "$2" "$3"
            return
            ;;
        --internal-repackage)
            [[ $# -eq 3 ]] || die "invalid internal repackage invocation"
            recipe_run_internal_repackage "$2" "$3"
            return
            ;;
    esac

    while (($#)); do
        case $1 in
            --force) force=true ;;
            --skip-check) skip_check=true ;;
            --no-deps) no_dependencies=true ;;
            --repackage) repackage=true ;;
            *) die "unknown recipe option: $1" ;;
        esac
        shift
    done

    if [[ "$repackage" == true ]]; then
        [[ "$force" == false && "$skip_check" == false && "$no_dependencies" == false ]] || \
            die "--repackage cannot be combined with build options"
        recipe_repackage
        return
    fi

    recipe_session_initialize
    recipe_run "$force" "$skip_check" "$no_dependencies"
}
