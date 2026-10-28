#!/usr/bin/env bash

# Intune discovery returns JSON by default; --debug prints local diagnostics.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "${0##*/}" == managed-compliance && $# -eq 0 ]]; then
    set -- --debug
fi

debug=false
case "${1:-}" in
    '') [[ $# -eq 0 ]] || { printf 'Use --debug or no arguments.\n' >&2; exit 2; } ;;
    --debug)
        [[ $# -eq 1 ]] || { printf 'Use --debug or no arguments.\n' >&2; exit 2; }
        [[ $EUID -eq 0 ]] || { printf 'Run diagnostics with sudo bash %s --debug\n' "$0" >&2; exit 2; }
        debug=true
        ;;
    --help)
        printf 'Usage: bash %s [--debug]\nDefault: JSON as compliance.sh; diagnostics as managed-compliance.\n--debug: read-only local checks and evidence (requires root).\nDebug exit codes: 0 = all checks pass, 1 = failed checks, 2 = usage or permissions.\n' "$0"
        exit 0
        ;;
    *) printf 'Unknown argument: %s. Use --help.\n' "$1" >&2; exit 2 ;;
esac

bool_json() {
    [[ "$1" == true ]] && printf true || printf false
}

secure_boot=false
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    secure_boot=true
fi

disk_encryption=false
if command -v lsblk >/dev/null 2>&1 && lsblk -rno TYPE 2>/dev/null | grep -qx crypt; then
    disk_encryption=true
fi
if [[ "$disk_encryption" == false ]]; then
    for dm_uuid_file in /sys/class/block/dm-*/dm/uuid; do
        [[ -r "$dm_uuid_file" ]] || continue
        IFS= read -r dm_uuid 2>/dev/null < "$dm_uuid_file" || continue
        if [[ "$dm_uuid" =~ ^CRYPT-LUKS[12]-[[:xdigit:]]{32}- ]]; then
            disk_encryption=true
            break
        fi
    done
fi

defender_installed=false
defender_onboarded=false
defender_healthy=false
defender_rtp=false
if [[ -x /usr/bin/mdatp ]]; then
    defender_installed=true
    org_id="$(timeout 20s mdatp health --field org_id 2>/dev/null || true)"
    org_id="${org_id#\"}"
    org_id="${org_id%\"}"
    [[ "$org_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] && defender_onboarded=true
    [[ "$(timeout 20s mdatp health --field healthy 2>/dev/null || true)" == true ]] && defender_healthy=true
    [[ "$(timeout 20s mdatp health --field real_time_protection_enabled 2>/dev/null || true)" == true ]] && defender_rtp=true
fi

himmelblau_installed=false
[[ -x /usr/sbin/himmelblaud || -x /usr/bin/himmelblaud ]] && himmelblau_installed=true

intune_enrolled=false
for config in /var/cache/himmelblaud/himmelblau.conf /etc/himmelblau/himmelblau.conf; do
    [[ -r "$config" ]] || continue
    device_id="$(sed -nE 's/^[[:space:]]*intune_device_id[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' "$config" | head -n 1)"
    if [[ "$device_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
        intune_enrolled=true
        break
    fi
done

if [[ "$debug" == true ]]; then
    failed_checks=0
    report_check() {
        if [[ "$2" == true ]]; then
            printf 'PASS  %s\n' "$1"
        else
            printf 'FAIL  %s\n' "$1"
            failed_checks=$((failed_checks + 1))
        fi
    }
    show_evidence() {
        printf '\n> %s\n' "$*"
        timeout 20s "$@" 2>&1
        evidence_status=$?
        if [[ $evidence_status -ne 0 ]]; then
            printf 'Diagnostic command failed or unavailable (exit %s; 124 means timeout).\n' "$evidence_status"
        fi
        return 0
    }

    printf 'Local Linux compliance diagnostics (read-only)\n'
    printf 'These checks do not query Intune or confirm its latest compliance evaluation.\n\n'
    report_check SecureBootEnabled "$secure_boot"
    report_check DeviceEncryptionEnabled "$disk_encryption"
    report_check DefenderInstalled "$defender_installed"
    report_check DefenderOnboarded "$defender_onboarded"
    report_check DefenderHealthy "$defender_healthy"
    report_check DefenderRealTimeProtectionEnabled "$defender_rtp"
    report_check HimmelblauInstalled "$himmelblau_installed"
    report_check IntuneEnrollmentCompleted "$intune_enrolled"
    for service in mdatp himmelblaud himmelblaud-tasks; do
        service_active=false
        timeout 10s systemctl is-active --quiet "$service" && service_active=true
        report_check "Service: $service" "$service_active"
    done

    printf '\nEvidence (may contain device and organization identifiers):\n'
    show_evidence mokutil --sb-state
    show_evidence lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS
    show_evidence lsblk -rno TYPE
    printf '\nActive device-mapper UUIDs (sysfs):\n'
    for dm_uuid_file in /sys/class/block/dm-*/dm/uuid; do
        [[ -r "$dm_uuid_file" ]] || continue
        IFS= read -r dm_uuid 2>/dev/null < "$dm_uuid_file" || continue
        printf '%s: %s\n' "$dm_uuid_file" "$dm_uuid"
    done
    show_evidence findmnt -no SOURCE,FSTYPE /
    show_evidence mdatp health
    show_evidence systemctl --no-pager --full status mdatp himmelblaud himmelblaud-tasks
    printf '\nEnrollment config visibility:\n'
    for config in /var/cache/himmelblaud/himmelblau.conf /etc/himmelblau/himmelblau.conf; do
        if [[ -r "$config" ]]; then
            printf 'Readable: %s\n' "$config"
        else
            printf 'Missing or unreadable: %s\n' "$config"
        fi
    done
    printf '\n%s failed check(s). Enrollment means a local device ID was found, not cloud confirmation.\n' "$failed_checks"
    printf 'Encryption detection checks for any crypt device or active LUKS mapping, not full coverage of every data volume.\n'
    [[ $failed_checks -eq 0 ]] && exit 0
    exit 1
fi

printf '{"SecureBootEnabled":%s,"DeviceEncryptionEnabled":%s,"DefenderInstalled":%s,"DefenderOnboarded":%s,"DefenderHealthy":%s,"DefenderRealTimeProtectionEnabled":%s,"HimmelblauInstalled":%s,"IntuneEnrollmentCompleted":%s}\n' \
    "$(bool_json "$secure_boot")" \
    "$(bool_json "$disk_encryption")" \
    "$(bool_json "$defender_installed")" \
    "$(bool_json "$defender_onboarded")" \
    "$(bool_json "$defender_healthy")" \
    "$(bool_json "$defender_rtp")" \
    "$(bool_json "$himmelblau_installed")" \
    "$(bool_json "$intune_enrolled")"