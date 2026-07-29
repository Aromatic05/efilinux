#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/001-runtime/desktop-libraries/config.sh"
source "$ROOT/002-system/desktop-services/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command autoreconf curl gcc make meson ninja pkg-config sha256sum tar
ensure_directories

recipe_inputs=(
    "$ROOT/001-runtime/config.sh"
    "$ROOT/002-system/desktop-services/config.sh"
)

restore_package() {
    binary_package_restore_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

publish_package() {
    find "$PACKAGE_STAGING" -type f -name '*.la' -delete 2>/dev/null || true
    binary_package_publish_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

prepare_tar_package() {
    local package=$1 archive_name=$2 digest=$3 url=$4
    local archive="$EFILINUX_DOWNLOADS/$archive_name"
    prepare_package "$package"
    download "$url" "$archive"
    verify_sha256 "$digest" "$archive"
    extract_source "$archive" "$PACKAGE_SOURCE"
}

normalize_staged_sysroot_prefix() {
    local leaked_root="$PACKAGE_STAGING$EFILINUX_SYSROOT"

    if [[ -d "$leaked_root" ]]; then
        cp -a "$leaked_root/." "$PACKAGE_STAGING/"
        rm -rf "$PACKAGE_STAGING/home"
    fi

    if find "$PACKAGE_STAGING" -path "*$EFILINUX_SYSROOT*" -print -quit | grep -q .; then
        die "package contains an installation path prefixed by the target sysroot"
    fi
}

configure_target() {
    local source=$1
    shift
    (
        cd "$PACKAGE_BUILD"
        CC=gcc \
        CFLAGS="$(target_cflags)" \
        CPPFLAGS="--sysroot=$EFILINUX_SYSROOT" \
        LDFLAGS="$(target_ldflags)" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$source/configure" \
                --prefix=/usr \
                --libdir=/usr/lib \
                --sysconfdir=/etc \
                --localstatedir=/var \
                "$@"
    )
}

make_target() {
    make -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
}

meson_target() {
    local source=$1
    shift
    CC=gcc \
    CFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$source" \
            --prefix=/usr \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            "$@"
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" \
        meson install -C "$PACKAGE_BUILD"
}

package="device-mapper-$LVM2_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "lvm2-$LVM2_VERSION.tgz" "$LVM2_SHA256" \
        "https://sourceware.org/ftp/lvm2/LVM2.$LVM2_VERSION.tgz"
    (
        cd "$PACKAGE_BUILD"
        CONFIG_SHELL=/bin/bash \
        CC=gcc \
        CFLAGS="$(target_cflags)" \
        CPPFLAGS="--sysroot=$EFILINUX_SYSROOT" \
        LDFLAGS="$(target_ldflags)" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            "$PACKAGE_SOURCE/configure" \
                --prefix=/usr \
                --sbindir=/usr/bin \
                --libdir=/usr/lib \
                --sysconfdir=/etc \
                --localstatedir=/var \
                --enable-pkgconfig \
                --disable-readline \
                --disable-selinux \
                --disable-udev_sync \
                --disable-udev_rules \
                --disable-systemd-journal \
                --disable-use-lvmpolld \
                --without-systemd \
                --without-udev \
                --with-thin=none \
                --with-cache=none \
                --with-writecache=none \
                --with-default-dm-run-dir=/run
    )
    make -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS" device-mapper
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install_device-mapper
    rm -rf "$PACKAGE_STAGING/usr/lib/systemd"
    publish_package "$package"
fi

package="cryptsetup-$CRYPTSETUP_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$CRYPTSETUP_SHA256" \
        "https://www.kernel.org/pub/linux/utils/cryptsetup/v2.8/$package.tar.xz"
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --disable-asciidoc \
        --disable-external-tokens \
        --disable-ssh-token \
        --disable-luks2-reencryption \
        --disable-fips \
        --disable-pwquality \
        --disable-passwdqc \
        --disable-selinux \
        --disable-veritysetup \
        --disable-integritysetup \
        --enable-keyring \
        --enable-udev \
        --enable-blkid \
        --with-crypto_backend=openssl \
        --enable-internal-argon2 \
        --disable-libargon2 \
        --with-tmpfilesdir=no
    make_target
    rm -rf "$PACKAGE_STAGING/usr/lib/systemd"
    publish_package "$package"
fi

package="libbytesize-$LIBBYTESIZE_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$LIBBYTESIZE_SHA256" \
        "https://github.com/storaged-project/libbytesize/releases/download/$LIBBYTESIZE_VERSION/$package.tar.gz"
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --without-python3 \
        --without-gtk-doc \
        --without-tools
    make_target
    publish_package "$package"
fi

package="libnvme-$LIBNVME_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$LIBNVME_SHA256" \
        "https://github.com/linux-nvme/libnvme/archive/refs/tags/v$LIBNVME_VERSION.tar.gz"
    meson_target "$PACKAGE_SOURCE" \
        -Ddocs=false \
        -Ddocs-build=false \
        -Dexamples=false \
        -Dtests=false \
        -Dpython=disabled \
        -Dopenssl=enabled \
        -Dlibdbus=disabled \
        -Djson-c=enabled \
        -Dkeyutils=enabled \
        -Dliburing=disabled
    publish_package "$package"
fi


package="mdadm-$MDADM_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$MDADM_SHA256" \
        "https://git.kernel.org/pub/scm/utils/mdadm/mdadm.git/snapshot/mdadm-mdadm-$MDADM_VERSION.tar.gz"
    make -C "$PACKAGE_SOURCE" -j "$EFILINUX_JOBS" \
        CC=gcc \
        CXFLAGS="$(target_cflags)" \
        LDFLAGS="$(target_ldflags)" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        VERSION="$MDADM_VERSION" \
        BINDIR=/usr/bin \
        UDEVDIR=/usr/lib/udev \
        CHECK_RUN_DIR=0 \
        all
    make -C "$PACKAGE_SOURCE" \
        DESTDIR="$PACKAGE_STAGING" \
        BINDIR=/usr/bin \
        UDEVDIR=/usr/lib/udev \
        install-bin install-udev
    install -Dm644 /dev/null "$PACKAGE_STAGING/etc/mdadm.conf"
    rm -rf "$PACKAGE_STAGING/usr/share/man"
    publish_package "$package"
fi

package="libblockdev-$LIBBLOCKDEV_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$LIBBLOCKDEV_SHA256" \
        "https://github.com/storaged-project/libblockdev/releases/download/$LIBBLOCKDEV_VERSION/$package.tar.gz"
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --disable-tests \
        --without-python3 \
        --without-gtk-doc \
        --with-crypto \
        --without-escrow \
        --without-dm \
        --without-lvm \
        --without-lvm-dbus \
        --without-mpath \
        --with-mdraid \
        --without-btrfs \
        --without-s390 \
        --without-nvdimm \
        --with-nvme \
        --without-smart \
        --without-smartmontools \
        --without-tools \
        --with-loop \
        --with-swap \
        --with-fs \
        --with-part
    make_target
    publish_package "$package"
fi

package="udisks-$UDISKS_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$UDISKS_SHA256" \
        "https://github.com/storaged-project/udisks/archive/refs/tags/udisks-$UDISKS_VERSION.tar.gz"
    sed -i \
        -e 's|--sourcedir=$(top_srcdir) udisks-daemon-resources.xml|--sourcedir=$(top_srcdir) $(srcdir)/udisks-daemon-resources.xml|g' \
        "$PACKAGE_SOURCE/src/Makefile.am"
    (cd "$PACKAGE_SOURCE" && NOCONFIGURE=1 ./autogen.sh)
    configure_target "$PACKAGE_SOURCE" \
        --disable-static \
        --enable-daemon \
        --disable-man \
        --enable-acl \
        --disable-lvm2 \
        --disable-iscsi \
        --disable-btrfs \
        --disable-smart \
        --libexecdir=/usr/lib \
        --sbindir=/usr/bin \
        --with-udevdir=/usr/lib/udev \
        --with-systemdsystemunitdir=no \
        --with-tmpfilesdir=no \
        --with-modloaddir=no \
        --with-modprobedir=no
    make_target
    publish_package "$package"
fi

package="gvfs-$GVFS_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$GVFS_SHA256" \
        "https://gitlab.gnome.org/GNOME/gvfs/-/archive/$GVFS_VERSION/$package.tar.gz"
    meson_target "$PACKAGE_SOURCE" \
        -Dsystemduserunitdir=no \
        -Dtmpfilesdir=no \
        -Dprivileged_group=wheel \
        -Dadmin=true \
        -Darchive=true \
        -Dsftp=true \
        -Dudisks2=true \
        -Dfuse=true \
        -Dgcrypt=true \
        -Dgudev=true \
        -Dkeyring=true \
        -Dlogind=true \
        -Dafc=false \
        -Dafp=false \
        -Dburn=false \
        -Dcdda=false \
        -Ddnssd=false \
        -Dgoa=false \
        -Dgoogle=false \
        -Dgphoto2=false \
        -Dhttp=false \
        -Dmtp=false \
        -Dnfs=false \
        -Donedrive=false \
        -Dsmb=false \
        -Dwsdd=false \
        -Dbluray=false \
        -Dgcr=false \
        -Dlibusb=false \
        -Ddevel_utils=false \
        -Dinstalled_tests=false \
        -Dunit_tests=false \
        -Dman=false
    normalize_staged_sysroot_prefix
    publish_package "$package"
fi
