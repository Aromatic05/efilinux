#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk cmp grep sha256sum tar
ensure_directories

[[ -s "$EFILINUX_PACKAGE_INDEX" ]] || \
    die "binary package index is missing or empty"

package_count=0
declare -A seen_packages=()
while IFS=$'\t' read -r package fingerprint archive_name digest extra; do
    [[ -n "$package" ]] || continue
    [[ -z ${extra:-} ]] || die "invalid binary package index record: $package"
    [[ -n "$fingerprint" && -n "$archive_name" && -n "$digest" ]] || \
        die "incomplete binary package index record: $package"
    [[ -z ${seen_packages[$package]+present} ]] || \
        die "duplicate binary package index record: $package"
    seen_packages[$package]=1

    archive="$EFILINUX_PACKAGES/$archive_name"
    [[ -f "$archive" ]] || die "indexed binary package is missing: $archive_name"
    [[ -f "$archive.sha256" ]] || \
        die "binary package checksum sidecar is missing: $archive_name"
    [[ $(sha256sum "$archive" | awk '{print $1}') == "$digest" ]] || \
        die "binary package digest does not match the index: $archive_name"
    (cd "$EFILINUX_PACKAGES" && \
        sha256sum --check --status "$(basename -- "$archive.sha256")") || \
        die "binary package checksum sidecar is invalid: $archive_name"

    metadata=$(tar --extract --to-stdout --file "$archive" .PKGINFO)
    grep -Fxq 'format=1' <<<"$metadata" || \
        die "unsupported binary package format: $archive_name"
    grep -Fxq "name=$package" <<<"$metadata" || \
        die "binary package name mismatch: $archive_name"
    grep -Fxq "fingerprint=$fingerprint" <<<"$metadata" || \
        die "binary package fingerprint mismatch: $archive_name"
    tar --extract --to-stdout --file "$archive" .FILELIST >/dev/null
    tar --list --file "$archive" | \
        awk '$0 ~ /^\// || $0 ~ /(^|\/)\.\.($|\/)/ { exit 1 }' || \
        die "binary package contains an unsafe path: $archive_name"

    package_count=$((package_count + 1))
done < "$EFILINUX_PACKAGE_INDEX"

((package_count > 0)) || die "binary package index contains no packages"

required_packages=(
    "linux-$LINUX_VERSION"
    "linux-firmware-$LINUX_FIRMWARE_VERSION"
    "sof-firmware-$SOF_FIRMWARE_VERSION"
    "wireless-regdb-$WIRELESS_REGDB_VERSION"

    "linux-headers-$LINUX_VERSION"
    "glibc-$GLIBC_VERSION"
    "gcc-runtime-$GCC_RUNTIME_VERSION"
    "libffi-$LIBFFI_VERSION"
    "pcre2-$PCRE2_VERSION"
    "zlib-$ZLIB_VERSION"
    "xz-$XZ_VERSION"
    "zstd-$ZSTD_VERSION"
    "attr-$ATTR_VERSION"
    "acl-$ACL_VERSION"
    "libcap-$LIBCAP_VERSION"
    "libxcrypt-$LIBXCRYPT_VERSION"
    "lzo-$LZO_VERSION"
    "kmod-$KMOD_VERSION"
    "util-linux-$UTIL_LINUX_VERSION"
    "e2fsprogs-$E2FSPROGS_VERSION"
    "kbd-$KBD_VERSION"
    "iana-etc-$IANA_ETC_VERSION"
    "tzdata-$TZDATA_VERSION"
    "btrfs-progs-v$BTRFS_PROGS_VERSION"
    "inih-$INIH_VERSION"
    "userspace-rcu-$USERSPACE_RCU_VERSION"
    "xfsprogs-$XFS_PROGS_VERSION"
    "dosfstools-$DOSFSTOOLS_VERSION"
    "exfatprogs-$EXFATPROGS_VERSION"
    "ntfs-3g-$NTFS_3G_VERSION"
    "busybox-$BUSYBOX_VERSION"

    "openssl-$OPENSSL_VERSION"
    "Linux-PAM-$LINUX_PAM_VERSION"
    "shadow-$SHADOW_VERSION"
    "sysvinit-$SYSVINIT_VERSION"
    "sysklogd-$SYSKLOGD_VERSION"
    "systemd-$UDEV_SYSTEMD_VERSION"
    "expat-$EXPAT_VERSION"
    "dbus-$DBUS_VERSION"
    "cronie-$CRONIE_VERSION"
    "iproute2-$IPROUTE2_VERSION"
    "iputils-$IPUTILS_VERSION"
    "dhcpcd-$DHCPCD_VERSION"
    "openssh-$OPENSSH_VERSION"

    "xorg-util-macros-$XORG_UTIL_MACROS_VERSION"
    "xorgproto-$XORGPROTO_VERSION"
    "xcb-proto-$XCB_PROTO_VERSION"
    "xtrans-$XTRANS_VERSION"
    "libXau-$LIBXAU_VERSION"
    "libXdmcp-$LIBXDMCP_VERSION"
    "libxcb-$LIBXCB_VERSION"
    "libX11-$LIBX11_VERSION"
    "libXext-$LIBXEXT_VERSION"
    "libXfixes-$LIBXFIXES_VERSION"
    "libXrender-$LIBXRENDER_VERSION"
    "libXrandr-$LIBXRANDR_VERSION"
    "libXi-$LIBXI_VERSION"
    "libXtst-$LIBXTST_VERSION"
    "libXcursor-$LIBXCURSOR_VERSION"
    "libXdamage-$LIBXDAMAGE_VERSION"
    "libXcomposite-$LIBXCOMPOSITE_VERSION"
    "libXinerama-$LIBXINERAMA_VERSION"
    "libxshmfence-$LIBXSHMFENCE_VERSION"
    "libXxf86vm-$LIBXXF86VM_VERSION"
    "llvm-$LLVM_VERSION"
    "llvm-spirv-$LLVM_SPIRV_TRANSLATOR_VERSION"
    "llvm-spirv-host-$LLVM_SPIRV_TRANSLATOR_VERSION"
    "spirv-tools-$SPIRV_TOOLS_VERSION"
    "clang-headers-$LLVM_VERSION"
    "libclc-$LLVM_VERSION"
    "libpciaccess-$LIBPCIACCESS_VERSION"
    "libdrm-$LIBDRM_VERSION"
    "elfutils-$ELFUTILS_VERSION"
    "mesa-$MESA_VERSION"
    "libevdev-$LIBEVDEV_VERSION"
    "libinput-$LIBINPUT_VERSION"
    "xkeyboard-config-$XKEYBOARD_CONFIG_VERSION"
    "libxkbcommon-$LIBXKBCOMMON_VERSION"
    "libpng-$LIBPNG_VERSION"
    "libjpeg-turbo-$LIBJPEG_TURBO_VERSION"
    "freetype-bootstrap-$FREETYPE_VERSION"
    "fontconfig-$FONTCONFIG_VERSION"
    "harfbuzz-$HARFBUZZ_VERSION"
    "freetype-$FREETYPE_VERSION"
    "fribidi-$FRIBIDI_VERSION"
    "pixman-$PIXMAN_VERSION"
    "dejavu-fonts-$DEJAVU_FONTS_VERSION"
    "libepoxy-$LIBEPOXY_VERSION"
    "libXft-$LIBXFT_VERSION"
    "font-util-$FONT_UTIL_VERSION"
    "libfontenc-$LIBFONTENC_VERSION"
    "libXfont2-$LIBXFONT2_VERSION"
    "libxkbfile-$LIBXKBFILE_VERSION"
    "libxcvt-$LIBXCVT_VERSION"
    "xkbcomp-$XKBCOMP_VERSION"
    "xorg-server-$XORG_SERVER_VERSION"
    "xf86-input-libinput-$XF86_INPUT_LIBINPUT_VERSION"
    "xf86-video-fbdev-$XF86_VIDEO_FBDEV_VERSION"
    "xinit-$XINIT_VERSION"
    "xwininfo-$XWININFO_VERSION"
    "glib-$GLIB_VERSION"
    "libxml2-$LIBXML2_VERSION"
    "at-spi2-core-$AT_SPI2_CORE_VERSION"
    "gdk-pixbuf-$GDK_PIXBUF_VERSION"
    "cairo-$CAIRO_VERSION"
    "pango-$PANGO_VERSION"
    "gtk-$GTK3_VERSION"
    "libICE-$LIBICE_VERSION"
    "libSM-$LIBSM_VERSION"
    "libXt-$LIBXT_VERSION"
    "libXmu-$LIBXMU_VERSION"
    "xauth-$XAUTH_VERSION"
)

for package in "${required_packages[@]}"; do
    [[ -n ${seen_packages[$package]+present} ]] || \
        die "required binary package is missing from the index: $package"
done

for temporary in "$EFILINUX_PACKAGES"/*.tmp.*; do
    [[ -e "$temporary" ]] || continue
    die "unfinished binary package temporary file remains: $(basename -- "$temporary")"
done

materialized="$EFILINUX_TEST/package-xauth"
binary_package_materialize "xauth-$XAUTH_VERSION" "$materialized"
[[ -x "$materialized/usr/bin/xauth" ]] || \
    die "materialized xauth package does not contain /usr/bin/xauth"
rm -rf -- "$materialized"

linux_materialized="$EFILINUX_TEST/package-linux"
binary_package_materialize "linux-$LINUX_VERSION" "$linux_materialized"
[[ -f "$linux_materialized/boot/vmlinuz-$LINUX_VERSION" ]] || \
    die "materialized linux package does not contain /boot/vmlinuz-$LINUX_VERSION"
[[ -d "$linux_materialized/usr/lib/modules/$LINUX_VERSION" ]] || \
    die "materialized linux package does not contain its kernel modules"
[[ ! -e "$linux_materialized/EFI/BOOT/BOOTX64.EFI" ]] || \
    die "linux package must not encode the final EFILinux image"
[[ -f "$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI" ]] || \
    die "final EFILinux EFI executable is missing"
if cmp -s \
    "$linux_materialized/boot/vmlinuz-$LINUX_VERSION" \
    "$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"; then
    die "clean vmlinuz and final EFILinux EFI executable are incorrectly identical"
fi
rm -rf -- "$linux_materialized"

log "Binary package index, metadata, checksums, and payload extraction passed"
printf 'Indexed packages: %s\n' "$package_count"
