#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }
state_directory=/var/lib/linux-onboarding
[[ ! -f "$state_directory/ready" ]] || exit 0

services_ready=true
for service in mdatp himmelblaud himmelblaud-tasks; do
    if ! systemctl is-active --quiet "$service"; then
        printf 'Service not ready: %s. The readiness timer will retry.\n' "$service" >&2
        services_ready=false
    fi
done

if [[ "$services_ready" == true ]] && timeout 20s mdatp health --output json | jq -e '
        (.org_id | strings | test("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")) and
        .healthy == true and .real_time_protection_enabled == true
    ' >/dev/null; then
    install -d -m 0700 "$state_directory"
    touch "$state_directory/ready"
    printf 'Defender and Himmelblau are ready. Intune enrollment must be verified separately after Entra sign-in.\n'
    exit 0
fi

printf 'Initial readiness is not confirmed. The timer will retry; graphical sign-in remains available. Inspect this service journal from an administrator or recovery session.\n' >&2
exit 1