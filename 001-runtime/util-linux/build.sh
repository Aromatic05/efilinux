#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make pkg-config sha256sum tar
ensure_directories
package="util-linux-$UTIL_LINUX_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://www.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_VERSION%.*}/$package.tar.xz" "$archive"
verify_sha256 "$UTIL_LINUX_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring Util-linux"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    "$PACKAGE_SOURCE/configure" \
        --prefix=/usr \
        --bindir=/usr/bin \
        --sbindir=/usr/bin \
        --libdir=/usr/lib \
        --runstatedir=/run \
        --sysconfdir=/etc \
        --disable-static \
        --disable-chfn-chsh \
        --disable-login \
        --disable-nologin \
        --disable-su \
        --disable-runuser \
        --disable-pylibmount \
        --disable-makeinstall-chown \
        --disable-makeinstall-setuid \
        --without-python \
        --without-systemd \
        --without-udev \
        --without-ncursesw \
        --without-readline \
        --without-selinux \
        --without-audit \
        --without-cap-ng \
        --without-cryptsetup \
        --without-btrfs \
        --enable-rfkill
log "Building Util-linux"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
merge_sysroot "$PACKAGE_STAGING"
