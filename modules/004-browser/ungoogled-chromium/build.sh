#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=ungoogled-chromium
pkgver=117.0.5938.149-1.1
depends=(
    alsa-lib
    at-spi2-core
    cairo
    dbus
    expat
    fontconfig
    freetype
    gcc-libs
    gdk-pixbuf
    glib
    glibc
    gtk3
    libcups
    libdrm
    libxkbcommon
    mesa
    nspr
    nss
    pango
    xorg
)
builddepends=()
makedepends=()
sysroot=false

prepare() {
    local archive="$downloaddir/ungoogled-chromium_${pkgver}_linux.tar.xz"
    download "https://github.com/ungoogled-software/ungoogled-chromium-portablelinux/releases/download/117.0.5938.149-1/ungoogled-chromium_${pkgver}_linux.tar.xz" "$archive"
    checksum sha256 128ed23f63e1fa581bcf368bdd6de5c04da1fc716cae57aea524fffaec39eec3 "$archive"
}

build() {
    local archive source_root locale

    archive="$downloaddir/ungoogled-chromium_${pkgver}_linux.tar.xz"
    mkdir -p "$srcdir/unpacked"
    tar -xf "$archive" -C "$srcdir/unpacked"
    source_root="$srcdir/unpacked/ungoogled-chromium_${pkgver}_linux"

    install -d \
        "$develdir/opt/ungoogled-chromium" \
        "$develdir/usr/bin" \
        "$develdir/usr/share/applications" \
        "$develdir/usr/share/icons/hicolor/48x48/apps"
    cp -a "$source_root/." "$develdir/opt/ungoogled-chromium/"

    rm -f \
        "$develdir/opt/ungoogled-chromium/chromedriver" \
        "$develdir/opt/ungoogled-chromium/chrome_crashpad_handler" \
        "$develdir/opt/ungoogled-chromium/chrome-wrapper" \
        "$develdir/opt/ungoogled-chromium/chrome_sandbox" \
        "$develdir/opt/ungoogled-chromium/chrome_200_percent.pak" \
        "$develdir/opt/ungoogled-chromium/xdg-mime" \
        "$develdir/opt/ungoogled-chromium/xdg-settings"

    find "$develdir/opt/ungoogled-chromium/locales" -type f -name '*.pak.info' -delete
    while IFS= read -r -d '' locale; do
        case $(basename -- "$locale") in
            en-US.pak|zh-CN.pak) ;;
            *) rm -f -- "$locale" ;;
        esac
    done < <(find "$develdir/opt/ungoogled-chromium/locales" -type f -name '*.pak' -print0)

    cat > "$develdir/usr/bin/ungoogled-chromium" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

browser=/opt/ungoogled-chromium/chrome
root_flags=()
if [[ $(id -u) -eq 0 ]]; then
    root_flags+=(--no-sandbox)
fi

exec "$browser" \
    --disable-background-networking \
    --disable-breakpad \
    --disable-client-side-phishing-detection \
    --disable-component-update \
    --disable-domain-reliability \
    --disable-features=OptimizationGuideModelDownloading,OptimizationHints,OptimizationTargetPrediction,MediaRouter,Translate \
    --disable-sync \
    --no-default-browser-check \
    --no-first-run \
    "${root_flags[@]}" \
    "$@"
LAUNCHER
    chmod 0755 "$develdir/usr/bin/ungoogled-chromium"

    cat > "$develdir/usr/share/applications/ungoogled-chromium.desktop" <<'DESKTOP'
[Desktop Entry]
Version=1.0
Name=Ungoogled Chromium
Comment=Chromium 117 browser without Google web-service integration
Exec=ungoogled-chromium %U
Terminal=false
Type=Application
Icon=ungoogled-chromium
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
DESKTOP
    install -m0644 "$source_root/product_logo_48.png" \
        "$develdir/usr/share/icons/hicolor/48x48/apps/ungoogled-chromium.png"
}

devel() {
    chmod 0755 "$develdir/opt/ungoogled-chromium/chrome"
}

package() {
    package_keep \
        /opt/ungoogled-chromium/ \
        /usr/bin/ungoogled-chromium \
        /usr/share/applications/ungoogled-chromium.desktop \
        /usr/share/icons/hicolor/48x48/apps/ungoogled-chromium.png
}

recipe_main "$@"
