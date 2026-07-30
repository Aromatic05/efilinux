#!/usr/bin/env bash

set -euo pipefail

target_python_path() {
    find "$EFILINUX_SYSROOT/usr/lib" -type d -path '*/site-packages' -print 2>/dev/null |
        paste -sd: -
}

target_rebind_sysroot() {
    local new_sysroot=$1
    local old_sysroot=$EFILINUX_SYSROOT

    [[ $new_sysroot == /* && $new_sysroot != *..* ]] || \
        die "invalid target sysroot: $new_sysroot"
    [[ -d $new_sysroot ]] || die "target sysroot does not exist: $new_sysroot"
    [[ $new_sysroot != "$old_sysroot" ]] || return 0

    CFLAGS=${CFLAGS//"$old_sysroot"/"$new_sysroot"}
    CXXFLAGS=${CXXFLAGS//"$old_sysroot"/"$new_sysroot"}
    CPPFLAGS=${CPPFLAGS//"$old_sysroot"/"$new_sysroot"}
    LDFLAGS=${LDFLAGS//"$old_sysroot"/"$new_sysroot"}
    EFILINUX_SYSROOT=$new_sysroot
    export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS EFILINUX_SYSROOT
}

target_normalize_pkg_config() {
    local staging=$1
    local metadata

    while IFS= read -r -d '' metadata; do
        sed -i \
            -e "s# -I$EFILINUX_SYSROOT/usr/include##g" \
            -e "s# -L$EFILINUX_SYSROOT/usr/lib##g" \
            "$metadata"
    done < <(find "$staging/usr" -type f -name '*.pc' -print0 2>/dev/null)
}

target_compiler_wrapper() {
    local compiler=$1
    local wrapper_directory="$recipework/toolchain-wrappers"
    local wrapper="$wrapper_directory/$compiler"

    mkdir -p "$wrapper_directory"
    cat > "$wrapper" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

compiler_name=$(basename -- "$0")
case $compiler_name in
    gcc|g++) real_compiler="/usr/bin/$compiler_name" ;;
    *) printf 'unsupported compiler wrapper name: %s\n' "$compiler_name" >&2; exit 2 ;;
esac

sysroot=
for argument in "$@"; do
    case $argument in
        --sysroot=*) sysroot=${argument#--sysroot=} ;;
    esac
done

rewritten=()
for argument in "$@"; do
    if [[ -n $sysroot ]]; then
        case $argument in
            -L/usr/lib*|-L/lib*) argument="-L$sysroot${argument#-L}" ;;
        esac
    fi
    rewritten+=("$argument")
done

exec "$real_compiler" "${rewritten[@]}"
WRAPPER
    chmod 0755 "$wrapper"
    printf '%s' "$wrapper"
}

target_program_wrapper() {
    local name=$1
    local program=$2
    local wrapper_directory="$recipework/target-program-wrappers"
    local wrapper="$wrapper_directory/$name"

    [[ $program == /* && $program != *..* ]] || \
        die "invalid target program path: $program"
    [[ -x "$EFILINUX_SYSROOT$program" ]] || \
        die "target build program is missing: $program"
    [[ -x "$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" ]] || \
        die "target dynamic loader is missing"

    mkdir -p "$wrapper_directory"
    cat > "$wrapper" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH \\
    "$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \\
    --library-path "$EFILINUX_SYSROOT/usr/lib" \\
    "$EFILINUX_SYSROOT$program" "\$@"
WRAPPER
    chmod 0755 "$wrapper"
    printf '%s' "$wrapper"
}

target_meson_setup() {
    local source=$1
    local build=$2
    shift 2

    CC="$CC" \
    CXX="$CXX" \
    CFLAGS="$CFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    PYTHONPATH="$(target_python_path)" \
        meson setup "$build" "$source" \
            --prefix=/usr \
            --libdir=lib \
            --buildtype=release \
            --wrap-mode=nodownload \
            "$@"
}

target_meson_install() {
    local build=$1
    local staging=$2

    meson compile -C "$build" -j "$EFILINUX_JOBS"
    DESTDIR="$staging" meson install -C "$build"
    target_normalize_pkg_config "$staging"
}

target_autotools_configure() {
    local source=$1
    local build=$2
    shift 2

    (
        unset srcdir builddir
        cd "$source"
        ACLOCAL_PATH="$EFILINUX_SYSROOT/usr/share/aclocal" autoreconf -fi
    )
    (
        unset srcdir builddir
        cd "$build"
        CC="$(target_compiler_wrapper gcc)" \
        CXX="$(target_compiler_wrapper g++)" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PYTHON=/usr/bin/python3 \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        PYTHONPATH="$(target_python_path)" \
        ACLOCAL_PATH="$EFILINUX_SYSROOT/usr/share/aclocal" \
            "$source/configure" \
                --prefix=/usr \
                --libdir=/usr/lib \
                --with-sysroot="$EFILINUX_SYSROOT" \
                "$@"
    )
}

target_release_configure() {
    local source=$1
    local build=$2
    shift 2

    (
        unset srcdir builddir
        cd "$build"
        CC="$(target_compiler_wrapper gcc)" \
        CXX="$(target_compiler_wrapper g++)" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        PYTHON=/usr/bin/python3 \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        PYTHONPATH="$(target_python_path)" \
            "$source/configure" \
                --prefix=/usr \
                --libdir=/usr/lib \
                --with-sysroot="$EFILINUX_SYSROOT" \
                "$@"
    )
}

target_make_install() {
    local build=$1
    local staging=$2

    make -C "$build" -j"$EFILINUX_JOBS"
    make -C "$build" DESTDIR="$staging" install
    find "$staging/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
    target_normalize_pkg_config "$staging"
}

target_cmake_setup() {
    local source=$1
    local build=$2
    shift 2

    PKG_CONFIG_PATH= \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    cmake -S "$source" -B "$build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_C_COMPILER="$(target_compiler_wrapper gcc)" \
        -DCMAKE_CXX_COMPILER="$(target_compiler_wrapper g++)" \
        -DCMAKE_SYSROOT="$EFILINUX_SYSROOT" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_FIND_ROOT_PATH="$EFILINUX_SYSROOT" \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        "$@"
}

target_cmake_install() {
    local build=$1
    local staging=$2

    cmake --build "$build" -j "$EFILINUX_JOBS"
    DESTDIR="$staging" cmake --install "$build"
    target_normalize_pkg_config "$staging"
}

prune_translations() {
    local root=$1
    local locale_directory="$root/usr/share/locale"
    local entry

    [[ -d "$locale_directory" ]] || return 0
    while IFS= read -r -d '' entry; do
        case $(basename -- "$entry") in
            en|en_US|zh_CN|zh_Hans) ;;
            *) rm -rf -- "$entry" ;;
        esac
    done < <(find "$locale_directory" -mindepth 1 -maxdepth 1 -print0)
}
