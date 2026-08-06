#!/usr/bin/env bash

recovery_publish_usr_paths() {
    local root=$1
    local prefix=/opt/recovery
    local relative source destination
    shift

    for relative in "$@"; do
        case $relative in
            ''|/*|*'..'*) die "invalid recovery /usr path: $relative" ;;
        esac
        source="$root$prefix/$relative"
        destination="$root/usr/$relative"
        [[ -e "$source" || -L "$source" ]] ||
            die "recovery published source path is missing: $prefix/$relative"
        if [[ -d "$source" && ! -L "$source" ]]; then
            mkdir -p "$destination"
            cp -a "$source/." "$destination/"
            rm -rf -- "$source"
        else
            mkdir -p "$(dirname -- "$destination")"
            [[ ! -e "$destination" && ! -L "$destination" ]] ||
                die "recovery published /usr path already exists: /usr/$relative"
            mv -- "$source" "$destination"
        fi
    done
}

recovery_prune_translations() {
    local root=$1
    local locale_directory="$root/opt/recovery/share/locale"
    local entry

    [[ -d "$locale_directory" ]] || return 0
    while IFS= read -r -d '' entry; do
        case $(basename -- "$entry") in
            en|en_US|zh_CN|zh_Hans) ;;
            *) rm -rf -- "$entry" ;;
        esac
    done < <(find "$locale_directory" -mindepth 1 -maxdepth 1 -print0)
}
