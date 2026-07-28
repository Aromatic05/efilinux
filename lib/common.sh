#!/usr/bin/env bash

set -euo pipefail

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || \
            die "required host command not found: $command_name"
    done
}

ensure_directories() {
    mkdir -p \
        "$EFILINUX_DOWNLOADS" \
        "$EFILINUX_BUILD/sources" \
        "$EFILINUX_BUILD/staging" \
        "$EFILINUX_LOGS" \
        "$EFILINUX_STATE" \
        "$EFILINUX_TEST" \
        "$EFILINUX_TARGET" \
        "$EFILINUX_ROOTFS" \
        "$EFILINUX_SYSROOT"
}

download() {
    local url=$1
    local output=$2
    local partial="$output.part"
    local status

    [[ -f "$output" ]] && return

    if [[ -s "$partial" ]]; then
        log "Resuming $(basename -- "$output")"
        if curl \
            --continue-at - \
            --fail \
            --location \
            --retry 3 \
            --retry-all-errors \
            --output "$partial" \
            "$url"; then
            mv -- "$partial" "$output"
            return
        else
            status=$?
        fi

        if (( status != 33 )); then
            return "$status"
        fi

        log "Server does not support resuming; restarting $(basename -- "$output")"
        rm -f -- "$partial"
    fi

    log "Downloading $(basename -- "$output")"
    curl \
        --fail \
        --location \
        --retry 3 \
        --retry-all-errors \
        --output "$partial" \
        "$url"
    mv -- "$partial" "$output"
}

verify_md5() {
    local expected=$1
    local file=$2
    printf '%s  %s\n' "$expected" "$file" | md5sum --check --status - || \
        die "MD5 verification failed: $file"
}

verify_sha256() {
    local expected=$1
    local file=$2
    printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status - || \
        die "SHA-256 verification failed: $file"
}

reset_directory() {
    local directory=$1
    rm -rf -- "$directory"
    mkdir -p -- "$directory"
}

extract_source() {
    local archive=$1
    local destination=$2

    reset_directory "$destination"
    tar --extract --file "$archive" --strip-components=1 --directory "$destination"
}

run_component() {
    local component=$1
    shift
    log "Building ${component#"$EFILINUX_ROOT/"}"
    "$component/build.sh" "$@"
}
