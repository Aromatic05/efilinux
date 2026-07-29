#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/001-runtime/desktop-libraries/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command readelf sha256sum tar
ensure_directories

assembly="$EFILINUX_BUILD/assembly/runtime-rootfs"
reset_directory "$assembly"
package_materialization="$assembly/packages"
mkdir -p "$package_materialization"

stage() {
    local package=$1
    local directory="$package_materialization/$package"

    if [[ ! -d "$directory" ]]; then
        binary_package_materialize "$package" "$directory"
    fi
    printf '%s' "$directory"
}

busybox_staging=$(stage "busybox-$BUSYBOX_VERSION")
rootfs_directory="$EFILINUX_ROOTFS"
busybox_binary="$busybox_staging/bin/busybox"

[[ -x "$busybox_binary" ]] || die "BusyBox staging tree does not exist"
reset_directory "$rootfs_directory"
mkdir -p "$(dirname -- "$EFILINUX_ROOTFS_OWNERS")"
: > "$EFILINUX_ROOTFS_OWNERS"

log "Creating merged-/usr target rootfs"
mkdir -p \
    "$rootfs_directory/usr/bin" \
    "$rootfs_directory/usr/lib" \
    "$rootfs_directory/dev" \
    "$rootfs_directory/proc" \
    "$rootfs_directory/sys" \
    "$rootfs_directory/run" \
    "$rootfs_directory/tmp" \
    "$rootfs_directory/etc" \
    "$rootfs_directory/root"

ln -s usr/bin "$rootfs_directory/bin"
ln -s usr/bin "$rootfs_directory/sbin"
ln -s usr/lib "$rootfs_directory/lib"
ln -s usr/lib "$rootfs_directory/lib64"
ln -s bin "$rootfs_directory/usr/sbin"
chmod 1777 "$rootfs_directory/tmp"

cp "$busybox_binary" "$rootfs_directory/usr/bin/busybox"
record_rootfs_owner busybox /usr/bin/busybox
while IFS= read -r applet_name; do
    [[ "$applet_name" == busybox ]] && continue
    ln -s busybox "$rootfs_directory/usr/bin/$applet_name"
    record_rootfs_owner busybox "/usr/bin/$applet_name"
done < <(
    find "$busybox_staging" -type l -printf '%f\n' | sort -u
)

copy_program() {
    local package=$1
    local program=$2
    local source="$(stage "$package")/usr/bin/$program"
    install_rootfs_program "$package" "$source" "$program"
}

copy_runtime_libraries() {
    local package=$1
    local pattern=$2
    install_rootfs_library_family \
        "$package" \
        "$(stage "$package")" \
        "$pattern"
}

copy_runtime_libraries "zlib-$ZLIB_VERSION" 'libz.so.1*'
copy_runtime_libraries "xz-$XZ_VERSION" 'liblzma.so.5*'
copy_runtime_libraries "zstd-$ZSTD_VERSION" 'libzstd.so.1*'
for library in \
    'libglib-2.0.so.0*' \
    'libgobject-2.0.so.0*' \
    'libgio-2.0.so.0*' \
    'libgmodule-2.0.so.0*' \
    'libgthread-2.0.so.0*'; do
    copy_runtime_libraries "glib-$GLIB_VERSION" "$library"
done
copy_runtime_libraries "libyaml-$LIBYAML_VERSION" 'libyaml-0.so.2*'
copy_runtime_libraries "libexif-$LIBEXIF_VERSION" 'libexif.so.12*'
for runtime_spec in \
    "ncurses-$NCURSES_VERSION|libncursesw.so.6*" \
    "readline-$READLINE_VERSION|libreadline.so.8*" \
    "readline-$READLINE_VERSION|libhistory.so.8*" \
    "lua-$LUA_VERSION|liblua.so.5.4*" \
    "duktape-$DUKTAPE_VERSION|libduktape.so.207*" \
    "alsa-lib-$ALSA_LIB_VERSION|libasound.so.2*" \
    "ell-$ELL_VERSION|libell.so.0*" \
    "libnl-$LIBNL_VERSION|libnl-3.so.200*" \
    "libnl-$LIBNL_VERSION|libnl-genl-3.so.200*" \
    "libnl-$LIBNL_VERSION|libnl-route-3.so.200*" \
    "jansson-$JANSSON_VERSION|libjansson.so.4*" \
    "libndp-$LIBNDP_VERSION|libndp.so.0*" \
    "libarchive-$LIBARCHIVE_VERSION|libarchive.so.13*" \
    "fuse-$FUSE3_VERSION|libfuse3.so.4*" \
    "fuse-$FUSE3_VERSION|libfuse3.so.3*" \
    "sqlite-$SQLITE_VERSION|libsqlite3.so.0*" \
    "sqlite-$SQLITE_VERSION|libsqlite3.so.3*" \
    "dconf-$DCONF_VERSION|libdconf.so.1*" \
    "libgpg-error-$LIBGPG_ERROR_VERSION|libgpg-error.so.0*" \
    "libgcrypt-$LIBGCRYPT_VERSION|libgcrypt.so.20*" \
    "libsecret-$LIBSECRET_VERSION|libsecret-1.so.0*"; do
    package_name=${runtime_spec%%|*}
    library_pattern=${runtime_spec#*|}
    copy_runtime_libraries "$package_name" "$library_pattern"
done

for program in xz unxz xzcat; do
    copy_program "xz-$XZ_VERSION" "$program"
done
for program in zstd unzstd zstdcat; do
    copy_program "zstd-$ZSTD_VERSION" "$program"
done
for program in gdbus gio gio-querymodules glib-compile-schemas gsettings; do
    copy_program "glib-$GLIB_VERSION" "$program"
done
copy_program "dconf-$DCONF_VERSION" dconf
copy_program "fuse-$FUSE3_VERSION" fusermount3
if [[ -x "$(stage "libsecret-$LIBSECRET_VERSION")/usr/bin/secret-tool" ]]; then
    copy_program "libsecret-$LIBSECRET_VERSION" secret-tool
fi

for runtime_tree in gio glib-2.0; do
    source_tree="$(stage "glib-$GLIB_VERSION")/usr/lib/$runtime_tree"
    if [[ -d "$source_tree" ]]; then
        install_rootfs_tree glib "$source_tree" "/usr/lib/$runtime_tree"
    fi
done

for data_spec in \
    "alsa-lib-$ALSA_LIB_VERSION|/usr/share/alsa" \
    "gsettings-desktop-schemas-$GSETTINGS_SCHEMAS_VERSION|/usr/share/glib-2.0/schemas"; do
    package_name=${data_spec%%|*}
    data_path=${data_spec#*|}
    source_tree="$(stage "$package_name")$data_path"
    if [[ -d "$source_tree" ]]; then
        install_rootfs_tree "$package_name" "$source_tree" "$data_path"
    fi
done

if [[ -f "$(stage "fuse-$FUSE3_VERSION")/etc/fuse.conf" ]]; then
    install_rootfs_file "fuse-$FUSE3_VERSION" \
        "$(stage "fuse-$FUSE3_VERSION")/etc/fuse.conf" /etc/fuse.conf
fi

if [[ -d "$rootfs_directory/usr/share/glib-2.0/schemas" ]]; then
    "$rootfs_directory/usr/bin/glib-compile-schemas" \
        "$rootfs_directory/usr/share/glib-2.0/schemas"
    record_rootfs_owner glib /usr/share/glib-2.0/schemas/gschemas.compiled
fi

copy_glibc_runtime_file() {
    local file_name=$1
    local source_file="$(stage "glibc-$GLIBC_VERSION")/usr/lib/$file_name"

    [[ -e "$source_file" ]] || die "glibc runtime file is missing: $file_name"
    local resolved="$assembly/glibc/$file_name"
    mkdir -p "$(dirname -- "$resolved")"
    cp -aL "$source_file" "$resolved"
    install_rootfs_file glibc "$resolved" "/usr/lib/$file_name"
}

for runtime_file in \
    ld-linux-x86-64.so.2 \
    libc.so.6 \
    libdl.so.2 \
    libm.so.6 \
    libnss_dns.so.2 \
    libnss_files.so.2 \
    libpthread.so.0 \
    libresolv.so.2 \
    librt.so.1; do
    copy_glibc_runtime_file "$runtime_file"
done

copy_program "glibc-$GLIBC_VERSION" locale
install_rootfs_file \
    glibc \
    "$(stage "glibc-$GLIBC_VERSION")/usr/lib/locale/locale-archive" \
    /usr/lib/locale/locale-archive

cat > "$rootfs_directory/init" <<'INIT'
#!/bin/busybox sh

export PATH=/usr/bin
export HOME=/root
export TERM=linux

/usr/bin/mount -t proc proc /proc
/usr/bin/mount -t sysfs sysfs /sys
/usr/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || /usr/bin/true

/usr/bin/mdev -s
/usr/bin/mdev -d >/dev/null 2>&1 &
/usr/bin/hostname efilinux

/usr/bin/printf '\nEFI Linux initial runtime\n'
/usr/bin/printf '%s\n\n' "$(/usr/bin/busybox | /usr/bin/head -n 1)"
exec /usr/bin/setsid /usr/bin/cttyhack /usr/bin/sh
INIT
chmod 0755 "$rootfs_directory/init"
record_rootfs_owner runtime-base /init

cat > "$rootfs_directory/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/sh
PASSWD
cat > "$rootfs_directory/etc/group" <<'GROUP'
root:x:0:
GROUP
cat > "$rootfs_directory/etc/nsswitch.conf" <<'NSSWITCH'
passwd: files
group: files
shadow: files
hosts: files dns
NSSWITCH
cat > "$rootfs_directory/etc/hosts" <<'HOSTS'
127.0.0.1 localhost efilinux
::1 localhost efilinux
HOSTS
cat > "$rootfs_directory/etc/host.conf" <<'HOSTCONF'
multi on
HOSTCONF
cat > "$rootfs_directory/etc/resolv.conf" <<'RESOLV'
# Populated by the network configuration layer.
RESOLV
cat > "$rootfs_directory/etc/mdev.conf" <<'MDEV'
$MODALIAS=.* 0:0 660 @/usr/bin/modprobe "$MODALIAS"
MDEV

chmod 4755 "$rootfs_directory/usr/bin/fusermount3"

for base_file in \
    /etc/passwd /etc/group /etc/nsswitch.conf /etc/hosts \
    /etc/host.conf /etc/resolv.conf /etc/mdev.conf; do
    record_rootfs_owner runtime-base "$base_file"
done

log "Writing initramfs device manifest"
cat > "$EFILINUX_INITRAMFS_DEVICES" <<'DEVICES'
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
DEVICES
