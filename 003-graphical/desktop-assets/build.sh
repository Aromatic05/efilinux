#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command bash curl find install sha256sum tar
ensure_directories

noto_package="noto-sans-cjk-sc-$NOTO_SANS_CJK_VERSION"
if ! graphical_binary_package_restore "$noto_package"; then
    prepare_package "$noto_package"
    noto_font="$EFILINUX_DOWNLOADS/NotoSansCJKsc-Regular-$NOTO_SANS_CJK_VERSION.otf"
    download \
        "https://raw.githubusercontent.com/notofonts/noto-cjk/Sans$NOTO_SANS_CJK_VERSION/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf" \
        "$noto_font"
    verify_sha256 "$NOTO_SANS_CJK_SC_SHA256" "$noto_font"
    install -Dm644 \
        "$noto_font" \
        "$PACKAGE_STAGING/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf"
    graphical_binary_package_publish "$noto_package"
fi

qogir_package="qogir-icon-theme-$QOGIR_ICON_VERSION"
if ! graphical_binary_package_restore "$qogir_package"; then
    graphical_prepare_archive \
        "$qogir_package" \
        "qogir-icon-theme-$QOGIR_ICON_VERSION.tar.gz" \
        "$QOGIR_ICON_SHA256" \
        "https://github.com/vinceliuice/Qogir-icon-theme/archive/refs/tags/$QOGIR_ICON_VERSION.tar.gz"

    mkdir -p "$PACKAGE_STAGING/usr/share/icons"
    (
        cd "$PACKAGE_SOURCE"
        bash ./install.sh \
            --dest "$PACKAGE_STAGING/usr/share/icons" \
            --theme default \
            --color standard
    )

    rm -rf "$PACKAGE_STAGING/usr/share/icons/Qogir/cursors_scalable"
    if find -L "$PACKAGE_STAGING/usr/share/icons/Qogir" \
        -type l -print -quit | grep -q .; then
        die "Qogir icon package contains broken symbolic links"
    fi
    mapfile -t installed_variants < <(
        find "$PACKAGE_STAGING/usr/share/icons" \
            -maxdepth 1 -mindepth 1 -type d -name 'Qogir*' -printf '%f\n' | sort
    )
    [[ ${#installed_variants[@]} -eq 1 && ${installed_variants[0]} == Qogir ]] || \
        die "Qogir installation produced unexpected color variants"
    [[ -e "$PACKAGE_STAGING/usr/share/icons/Qogir/cursors/left_ptr" ]] || \
        die "Qogir cursor payload is incomplete"

    graphical_binary_package_publish "$qogir_package"
fi

qogir_theme_package="qogir-desktop-theme-$QOGIR_THEME_VERSION"
if ! graphical_binary_package_restore "$qogir_theme_package"; then
    graphical_prepare_archive \
        "$qogir_theme_package" \
        "qogir-theme-$QOGIR_THEME_VERSION.tar.gz" \
        "$QOGIR_THEME_SHA256" \
        "https://github.com/vinceliuice/Qogir-theme/archive/refs/tags/$QOGIR_THEME_VERSION.tar.gz"

    theme_directory="$PACKAGE_STAGING/usr/share/themes/Qogir"
    mkdir -p \
        "$theme_directory/gtk-2.0/assets" \
        "$theme_directory/gtk-3.0/assets" \
        "$theme_directory/gtk-4.0/assets/scalable" \
        "$theme_directory/xfwm4"

    cat > "$theme_directory/index.theme" <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Qogir
Comment=EFILinux Qogir desktop theme

[X-GNOME-Metatheme]
GtkTheme=Qogir
MetacityTheme=Qogir
IconTheme=Qogir
CursorTheme=Qogir
ButtonLayout=menu:minimize,maximize,close
EOF

    install -m644 \
        "$PACKAGE_SOURCE/src/gtk-2.0/theme/gtkrc" \
        "$theme_directory/gtk-2.0/gtkrc"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk-2.0/"*.rc \
        "$theme_directory/gtk-2.0/"
    cp -a "$PACKAGE_SOURCE/src/gtk-2.0/assets/assets/." \
        "$theme_directory/gtk-2.0/assets/"

    cp -a "$PACKAGE_SOURCE/src/gtk/assets/assets/." \
        "$theme_directory/gtk-3.0/assets/"
    cp -a "$PACKAGE_SOURCE/src/gtk/assets/assets-common/." \
        "$theme_directory/gtk-3.0/assets/"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/assets/logos/logo-.svg" \
        "$theme_directory/gtk-3.0/assets/logo.svg"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/assets/logos/logo@2-.svg" \
        "$theme_directory/gtk-3.0/assets/logo@2.svg"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/theme-3.0/gtk.css" \
        "$theme_directory/gtk-3.0/gtk.css"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/theme-3.0/gtk-Dark.css" \
        "$theme_directory/gtk-3.0/gtk-dark.css"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/assets/thumbnail.png" \
        "$theme_directory/gtk-3.0/thumbnail.png"

    cp -a "$theme_directory/gtk-3.0/assets/." \
        "$theme_directory/gtk-4.0/assets/"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/assets/assets-common/check-symbolic.svg" \
        "$PACKAGE_SOURCE/src/gtk/assets/assets-common/check-symbolic@2.svg" \
        "$theme_directory/gtk-4.0/assets/scalable/"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/theme-4.0/gtk.css" \
        "$theme_directory/gtk-4.0/gtk.css"
    install -m644 \
        "$PACKAGE_SOURCE/src/gtk/theme-4.0/gtk-Dark.css" \
        "$theme_directory/gtk-4.0/gtk-dark.css"

    install -m644 \
        "$PACKAGE_SOURCE/src/xfwm4/themerc" \
        "$theme_directory/xfwm4/themerc"
    install -m644 \
        "$PACKAGE_SOURCE/src/xfwm4/assets/"*.png \
        "$theme_directory/xfwm4/"
    cp -a "$PACKAGE_SOURCE/src/xfce-notify-4.0" \
        "$theme_directory/xfce-notify-4.0"

    for excluded in \
        cinnamon gnome-shell labwc metacity-1 plank unity; do
        [[ ! -e "$theme_directory/$excluded" ]] || \
            die "Qogir desktop theme contains excluded subtree: $excluded"
    done
    graphical_binary_package_publish "$qogir_theme_package"
fi
