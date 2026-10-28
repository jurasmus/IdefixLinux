#!/bin/bash -p
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C.UTF-8

device_name_for_account() {
    local display_name="$1" account="$2" identifier="$3" first_name
    display_name="${display_name%%,*}"
    if [[ -z "$display_name" || "$display_name" == *@* ]]; then
        display_name="${account%%@*}"
        display_name="${display_name%%[._-]*}"
    fi
    first_name="$(printf '%s' "$display_name" | awk '{print $1; exit}' |
        iconv -f UTF-8 -t ASCII//TRANSLIT | tr '[:upper:]' '[:lower:]' |
        tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//' | cut -c 1-32)"
    [[ -n "$first_name" ]] || first_name=user
    [[ "$identifier" =~ ^[a-f0-9]{32}$ ]] || return 1
    printf 'ubuntu-%s-%s\n' "$first_name" "${identifier:0:8}"
}

write_device_name() {
    local device_name="$1" hosts_file
    hosts_file="$(mktemp /etc/.linux-onboarding-hosts.XXXXXX)" || return 1
    if ! awk -v name="$device_name" '
        $1 == "127.0.1.1" { if (!seen++) print "127.0.1.1\t" name; next }
        { print }
        END { if (!seen) print "127.0.1.1\t" name }
    ' /etc/hosts >"$hosts_file"; then
        rm -f -- "$hosts_file"
        return 1
    fi
    if ! { install -m 0644 "$hosts_file" /etc/hosts &&
        printf '%s\n' "$device_name" >"$hosts_file" &&
        install -m 0644 "$hosts_file" /etc/hostname; }; then
        rm -f -- "$hosts_file"
        return 1
    fi
    rm -f -- "$hosts_file"
}

configure_device_name() {
    local mode="${1:-}" state_directory=/var/lib/linux-onboarding
    local identifier device_name record account password account_uid account_gid display_name home_directory login_shell lock_descriptor
    [[ $EUID -eq 0 ]] || { printf 'Run as root.\n' >&2; return 1; }
    [[ "$mode" == --initial || "$mode" == --first-login ]] || return 1
    if [[ "$mode" == --first-login ]]; then
        [[ "${PAM_TYPE:-}" == open_session && -n "${PAM_USER:-}" ]] || return 0
        case "${PAM_SERVICE:-}" in
            login|sshd|gdm-password|gdm-smartcard|gdm-fingerprint) ;;
            *) return 0 ;;
        esac
        [[ ! -f "$state_directory/hostname-set" ]] || return 0
        record="$(timeout 5s getent passwd "$PAM_USER")" || return 1
        IFS=: read -r account password account_uid account_gid display_name home_directory login_shell <<<"$record"
        [[ "$account_uid" =~ ^[0-9]+$ ]] || return 1
        [[ "$account_uid" -ge 6000000 && "$account_uid" -le 6999999 ]] || return 0
    fi
    install -d -m 0700 "$state_directory"
    exec {lock_descriptor}>"$state_directory/device-name.lock"
    flock -n "$lock_descriptor" || return 0
    if [[ "$mode" == --initial ]]; then
        [[ ! -f "$state_directory/device-name-id" ]] || return 0
        read -r identifier </proc/sys/kernel/random/uuid
        identifier="${identifier//-/}"
        [[ "$identifier" =~ ^[a-f0-9]{32}$ ]] || return 1
        device_name="ubuntu-${identifier:0:8}"
        write_device_name "$device_name" || return 1
        install -d -m 0755 /etc/cloud/cloud.cfg.d
        printf 'preserve_hostname: true\nmanage_etc_hosts: false\n' >/etc/cloud/cloud.cfg.d/99-linux-onboarding-hostname.cfg
        printf '%s\n' "$identifier" >"$state_directory/device-name-id"
    else
        [[ ! -f "$state_directory/hostname-set" ]] || return 0
        read -r identifier <"$state_directory/device-name-id"
        device_name="$(device_name_for_account "$display_name" "$account" "$identifier")"
        timeout 15s hostnamectl set-hostname "$device_name" || return 1
        write_device_name "$device_name" || return 1
        printf '%s\n' "$device_name" >"$state_directory/hostname-set"
    fi
    logger -t linux-device-name -- "Configured device hostname: $device_name" || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    umask 077
    configure_device_name "$@"
fi