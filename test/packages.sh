#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/002-system/desktop-config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/003-graphical/desktop-support/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk cmp gcc grep sha256sum tar
ensure_directories

target_gcc_runtime="$EFILINUX_SYSROOT/usr/lib/gcc/$EFILINUX_TOOLCHAIN_TRIPLET/$GCC_RUNTIME_VERSION"
expected_crtfastmath="$target_gcc_runtime/crtfastmath.o"
selected_crtfastmath=$(gcc $(target_ldflags) -print-file-name=crtfastmath.o)
[[ -f "$expected_crtfastmath" ]] || \
    die "target GCC crtfastmath.o is missing"
[[ "$selected_crtfastmath" == "$expected_crtfastmath" ]] || \
    die "target linker selects host crtfastmath.o: $selected_crtfastmath"

[[ -s "$EFILINUX_PACKAGE_INDEX" ]] || \
    die "binary package index is missing or empty"

for build_script in \
    "$ROOT/001-runtime/glib/build.sh" \
    "$ROOT/002-system/libgudev/build.sh" \
    "$ROOT/003-graphical/clang/build.sh" \
    "$ROOT/003-graphical/lib/build.sh"; do
    if grep -Fq 'LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib' "$build_script"; then
        die "host build process is polluted by target LD_LIBRARY_PATH: ${build_script#"$ROOT/"}"
    fi
done

package_count=0
current_package_count=0
legacy_package_count=0
declare -A seen_packages=()
declare -A package_formats=()
declare -A package_archives=()
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
    format=$(awk -F= '$1 == "format" { print $2; exit }' <<<"$metadata")
    [[ -n "$format" ]] || die "binary package format is missing: $archive_name"
    package_formats[$package]=$format
    package_archives[$package]=$archive_name
    grep -Fxq "name=$package" <<<"$metadata" || \
        die "binary package name mismatch: $archive_name"
    grep -Fxq "fingerprint=$fingerprint" <<<"$metadata" || \
        die "binary package fingerprint mismatch: $archive_name"
    tar --extract --to-stdout --file "$archive" .FILELIST >/dev/null
    tar --list --file "$archive" | \
        awk '$0 ~ /^\// || $0 ~ /(^|\/)\.\.($|\/)/ { exit 1 }' || \
        die "binary package contains an unsafe path: $archive_name"
    if [[ "$format" == "$BINARY_PACKAGE_FORMAT" ]]; then
        if LC_ALL=C tar --list --verbose --file "$archive" | \
            grep -F ' -> pkg/' >/dev/null; then
            die "binary package rewrites a symbolic-link target: $archive_name"
        fi
        if LC_ALL=C tar --list --verbose --file "$archive" | \
            grep -F ' link to ./' >/dev/null; then
            die "binary package does not rewrite a hard-link target: $archive_name"
        fi
        current_package_count=$((current_package_count + 1))
    else
        legacy_package_count=$((legacy_package_count + 1))
    fi

    package_count=$((package_count + 1))
done < "$EFILINUX_PACKAGE_INDEX"

((package_count > 0)) || die "binary package index contains no packages"
((current_package_count > 0)) || die "binary package index contains no current-format packages"

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
    "glib-$GLIB_VERSION"
    "libyaml-$LIBYAML_VERSION"
    "libexif-$LIBEXIF_VERSION"
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
    "libgudev-$LIBGUDEV_VERSION"
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
    "librsvg-$LIBRSVG_VERSION"
    "gtk-$GTK3_VERSION"
    "libICE-$LIBICE_VERSION"
    "libSM-$LIBSM_VERSION"
    "libXt-$LIBXT_VERSION"
    "libXmu-$LIBXMU_VERSION"
    "xauth-$XAUTH_VERSION"
    "iceauth-$ICEAUTH_VERSION"
    "noto-sans-cjk-sc-$NOTO_SANS_CJK_VERSION"
    "qogir-icon-theme-$QOGIR_ICON_VERSION"
    "qogir-desktop-theme-$QOGIR_THEME_VERSION"
    "xcb-util-$XCB_UTIL_VERSION"
    "libXres-$LIBXRES_VERSION"
    "libXpresent-$LIBXPRESENT_VERSION"
    "startup-notification-$STARTUP_NOTIFICATION_VERSION"
    "libnotify-$LIBNOTIFY_VERSION"
    "libwnck-$LIBWNCK_VERSION"

    "libxfce4util-$LIBXFCE4UTIL_VERSION"
    "xfconf-$XFCONF_VERSION"
    "libxfce4ui-$LIBXFCE4UI_VERSION"
    "exo-$EXO_VERSION"
    "garcon-$GARCON_VERSION"
    "thunar-$THUNAR_VERSION"
    "tumbler-$TUMBLER_VERSION"
    "xfce4-appfinder-$XFCE4_APPFINDER_VERSION"
    "xfce4-panel-$XFCE4_PANEL_VERSION"
    "xfce4-session-$XFCE4_SESSION_VERSION"
    "xfce4-settings-$XFCE4_SETTINGS_VERSION"
    "xfdesktop-$XFDESKTOP_VERSION"
    "xfwm4-$XFWM4_VERSION"
)

for package in "${required_packages[@]}"; do
    [[ -n ${seen_packages[$package]+present} ]] || \
        die "required binary package is missing from the index: $package"
done

for temporary in "$EFILINUX_PACKAGES"/*.tmp.*; do
    [[ -e "$temporary" ]] || continue
    die "unfinished binary package temporary file remains: $(basename -- "$temporary")"
done

extract_indexed_payload() {
    local package=$1
    local destination=$2
    local archive_name=${package_archives[$package]:-}
    local temporary="$destination.tmp"

    [[ -n "$archive_name" ]] || die "package archive is unknown: $package"
    reset_directory "$temporary"
    tar --extract --file "$EFILINUX_PACKAGES/$archive_name" \
        --directory "$temporary" pkg
    [[ -d "$temporary/pkg" ]] || die "binary package payload is missing: $archive_name"
    rm -rf -- "$destination"
    mv "$temporary/pkg" "$destination"
    rm -rf -- "$temporary"
}

materialized="$EFILINUX_TEST/package-tumbler"
binary_package_materialize "tumbler-$TUMBLER_VERSION" "$materialized"
[[ -f "$materialized/usr/lib/tumbler-1/plugins/tumbler-jpeg-thumbnailer.so" ]] || \
    die "materialized Tumbler package does not contain its JPEG plugin"
rm -rf -- "$materialized"

qogir_icon_materialized="$EFILINUX_TEST/package-qogir-icons"
qogir_theme_materialized="$EFILINUX_TEST/package-qogir-theme"
extract_indexed_payload \
    "qogir-icon-theme-$QOGIR_ICON_VERSION" "$qogir_icon_materialized"
extract_indexed_payload \
    "qogir-desktop-theme-$QOGIR_THEME_VERSION" "$qogir_theme_materialized"
[[ -f "$qogir_icon_materialized/usr/share/icons/Qogir/index.theme" ]] || \
    die "Qogir icon package does not contain its icon theme"
if find -L "$qogir_icon_materialized/usr/share/icons/Qogir" \
    -type l -print -quit | grep -q .; then
    die "Qogir icon package contains broken symbolic links"
fi
[[ ! -e "$qogir_icon_materialized/usr/share/themes" ]] || \
    die "Qogir icon package incorrectly contains desktop themes"
[[ -f "$qogir_theme_materialized/usr/share/themes/Qogir/gtk-2.0/gtkrc" ]] || \
    die "Qogir desktop theme package does not contain its GTK 2 theme"
[[ -f "$qogir_theme_materialized/usr/share/themes/Qogir/gtk-3.0/gtk.css" ]] || \
    die "Qogir desktop theme package does not contain its GTK 3 theme"
[[ -f "$qogir_theme_materialized/usr/share/themes/Qogir/gtk-4.0/gtk.css" ]] || \
    die "Qogir desktop theme package does not contain its GTK 4 theme"
[[ -f "$qogir_theme_materialized/usr/share/themes/Qogir/xfwm4/themerc" ]] || \
    die "Qogir desktop theme package does not contain its XFWM theme"
[[ ! -e "$qogir_theme_materialized/usr/share/icons" ]] || \
    die "Qogir desktop theme package incorrectly contains icon themes"
rm -rf -- "$qogir_icon_materialized" "$qogir_theme_materialized"

librsvg_materialized="$EFILINUX_TEST/package-librsvg"
extract_indexed_payload "librsvg-$LIBRSVG_VERSION" "$librsvg_materialized"
[[ -e "$librsvg_materialized/usr/lib/librsvg-2.so.2" ]] || \
    die "librsvg package does not contain its runtime library"
[[ -f "$librsvg_materialized/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-svg.so" ]] || \
    die "librsvg package does not contain the GdkPixbuf SVG loader"
rm -rf -- "$librsvg_materialized"

linux_materialized="$EFILINUX_TEST/package-linux"
extract_indexed_payload "linux-$LINUX_VERSION" "$linux_materialized"
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
printf 'Current-format packages: %s\n' "$current_package_count"
printf 'Legacy cached packages: %s\n' "$legacy_package_count"
