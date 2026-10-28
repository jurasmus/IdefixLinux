#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf -- "$workspace"' EXIT
payload_directory="${1:-$workspace/payload}"
python3 - "$script_directory/build-onboarding-iso.sh" "${1:-}" <<'PYTHON'
import pathlib
import sys
import yaml

if sys.argv[2]:
    payload = (pathlib.Path(sys.argv[2]).parent / 'autoinstall.yaml').read_text()
else:
    source = pathlib.Path(sys.argv[1]).read_text()
    payload = source.split("<<'AUTOINSTALL'\n", 1)[1].split('\nAUTOINSTALL', 1)[0]
config = yaml.safe_load(payload)['autoinstall']
assert config['interactive-sections'] == ['locale', 'keyboard', 'network', 'storage']
assert config['user-data']['users'] == []
assert config['apt']['fallback'] == 'offline-install'
assert config['refresh-installer']['update'] is False
print('PASS: language, keyboard, network and storage are interactive; offline and no-local-account settings remain intact.')
PYTHON
for script in "$script_directory/"*.sh "$script_directory/../tests/"*.sh "$script_directory/../compliance/"*.sh; do
    bash -n "$script"
done
for layout in repository iso; do
    layout_directory="$workspace/$layout layout"
    if [[ "$layout" == repository ]]; then
        onboarding_directory="$layout_directory/scripts"
        compliance_directory="$layout_directory/compliance"
    else
        onboarding_directory="$layout_directory/onboarding"
        compliance_directory="$onboarding_directory"
    fi
    mkdir -p "$onboarding_directory" "$compliance_directory"
    cp "$script_directory/../compliance/compliance.sh" "$compliance_directory/"
    awk '/^HIMMELBLAU_DOMAIN=/ { exit } { print }' "$script_directory/onboard-linux.sh" >"$onboarding_directory/onboard-linux.sh"
    printf 'test -r "$compliance_script"\nrealpath -- "$compliance_script"\n' >>"$onboarding_directory/onboard-linux.sh"
    [[ "$(bash "$onboarding_directory/onboard-linux.sh")" == "$compliance_directory/compliance.sh" ]]
done
(
    iso_tree="$workspace/packaging"
    compliance_directory="$(cd -- "$script_directory/../compliance" && pwd)"
    onboarding_file="$workspace/test-onboarding.json"
    domain=contoso.com
    printf '{}\n' >"$onboarding_file"
    source <(awk '
        /^payload_directory=/ { active=1 }
        active && /^if \[\[ -z "\$package_directory"/ { exit }
        active { print }
    ' "$script_directory/build-onboarding-iso.sh")
    cmp "$compliance_directory/compliance.sh" "$payload_directory/compliance.sh"
    [[ -s "$payload_directory/onboard-linux.sh" && -s "$payload_directory/configure-device-name.sh" ]]
)
printf 'PASS: relocated scripts parse; repository and flat ISO compliance lookup and ISO payload assembly validate, including paths with spaces.\n'
if [[ $# -eq 0 ]]; then
    mkdir -p "$payload_directory"
    for payload in install-target.sh linux-onboarding-ready.service linux-onboarding-ready.timer gdm-onboarding.conf linux-desktop-cleanup.service linux-desktop-cleanup.timer; do
        awk -v payload="$payload" '
            index($0, "cat >\"$payload_directory/" payload "\"") == 1 { active=1; next }
            active && /^[A-Z_]+$/ { exit }
            active { print }
        ' "$script_directory/build-onboarding-iso.sh" >"$payload_directory/$payload"
    done
    cp "$script_directory/verify-first-boot.sh" "$payload_directory/"
    cp "$script_directory/cleanup-desktop-apps.sh" "$payload_directory/"
    cp "$script_directory/configure-device-name.sh" "$payload_directory/"
    cp "$script_directory/configure-desktop-defaults.sh" "$payload_directory/"
fi
for payload in install-target.sh verify-first-boot.sh cleanup-desktop-apps.sh configure-device-name.sh configure-desktop-defaults.sh linux-onboarding-ready.service linux-onboarding-ready.timer gdm-onboarding.conf linux-desktop-cleanup.service linux-desktop-cleanup.timer; do
    [[ -s "$payload_directory/$payload" ]]
done
bash -n "$payload_directory/install-target.sh" "$payload_directory/verify-first-boot.sh"
! grep -Eq '^Before=|^WantedBy=' "$payload_directory/linux-desktop-cleanup.service"
grep -Fxq 'TimeoutStartSec=360' "$payload_directory/linux-desktop-cleanup.service"
grep -Fxq 'WantedBy=timers.target' "$payload_directory/linux-desktop-cleanup.timer"
grep -Fxq 'OnUnitInactiveSec=2min' "$payload_directory/linux-desktop-cleanup.timer"
grep -Fxq 'curtin in-target -- bash /opt/linux-onboarding/cleanup-desktop-apps.sh --packages' "$payload_directory/install-target.sh"
grep -Fxq 'curtin in-target -- systemctl enable linux-desktop-cleanup.timer' "$payload_directory/install-target.sh"
grep -Fxq 'curtin in-target -- bash /opt/linux-onboarding/configure-device-name.sh --initial' "$payload_directory/install-target.sh"
grep -Fxq 'curtin in-target -- bash /opt/linux-onboarding/configure-desktop-defaults.sh' "$payload_directory/install-target.sh"
! grep -Eq 'Requires=|linux-onboarding-ready|network-online' "$payload_directory/gdm-onboarding.conf"
grep -Fxq 'Wants=himmelblaud.service himmelblaud-tasks.service' "$payload_directory/gdm-onboarding.conf"
grep -Fxq 'After=himmelblaud.service himmelblaud-tasks.service' "$payload_directory/gdm-onboarding.conf"
! grep -Eq '^Before=|^WantedBy=|^RemainAfterExit=' "$payload_directory/linux-onboarding-ready.service"
grep -Fxq 'TimeoutStartSec=45' "$payload_directory/linux-onboarding-ready.service"
grep -Fxq 'WantedBy=timers.target' "$payload_directory/linux-onboarding-ready.timer"
grep -Fxq 'OnBootSec=30s' "$payload_directory/linux-onboarding-ready.timer"
grep -Fxq 'OnUnitInactiveSec=2min' "$payload_directory/linux-onboarding-ready.timer"
grep -Fxq 'curtin in-target -- systemctl enable linux-onboarding-ready.timer gdm.service' "$payload_directory/install-target.sh"
grep -Fxq 'curtin in-target -- systemctl set-default graphical.target' "$payload_directory/install-target.sh"
grep -Fxq "printf '[daemon]\\nInitialSetupEnable=false\\n' >/target/etc/gdm3/custom.conf" "$payload_directory/install-target.sh"
grep -Fxq "printf '[org/gnome/login-screen]\\ndisable-user-list=false\\n' >/target/etc/dconf/db/gdm.d/01-entra-login" "$payload_directory/install-target.sh"

root_directory="$workspace/root"
unit_directory="$root_directory/etc/systemd/system"
mkdir -p "$unit_directory/display-manager.service.d" "$root_directory/bin"
cp /bin/bash /usr/bin/true "$root_directory/bin/"
install -m 0644 "$payload_directory/linux-onboarding-ready.service" "$payload_directory/linux-onboarding-ready.timer" "$unit_directory/"
install -m 0644 "$payload_directory/linux-desktop-cleanup.service" "$payload_directory/linux-desktop-cleanup.timer" "$unit_directory/"
install -m 0644 "$payload_directory/gdm-onboarding.conf" "$unit_directory/display-manager.service.d/onboarding.conf"
for target in sysinit basic shutdown timers multi-user graphical; do
    printf '[Unit]\nDescription=Test %s target\nDefaultDependencies=no\n' "$target" >"$unit_directory/$target.target"
done
printf 'Requires=multi-user.target\nWants=display-manager.service\nAfter=multi-user.target display-manager.service\n' >>"$unit_directory/graphical.target"
for service in mdatp himmelblaud himmelblaud-tasks snapd gdm; do
    printf '[Service]\nExecStart=/bin/true\n' >"$unit_directory/$service.service"
done
printf '\n[Install]\nAlias=display-manager.service\n' >>"$unit_directory/gdm.service"
systemctl --root="$root_directory" enable linux-onboarding-ready.timer linux-desktop-cleanup.timer gdm.service
systemctl --root="$root_directory" set-default graphical.target
[[ "$(readlink "$unit_directory/default.target")" == */graphical.target ]]
[[ -L "$unit_directory/timers.target.wants/linux-onboarding-ready.timer" ]]
[[ -L "$unit_directory/display-manager.service" ]]
systemd-analyze --root="$root_directory" --generators=no verify \
    linux-onboarding-ready.service linux-onboarding-ready.timer linux-desktop-cleanup.service linux-desktop-cleanup.timer display-manager.service graphical.target
printf 'PASS: generated units validate; GDM and graphical target are enabled without a readiness dependency.\n'

mkdir "$workspace/bin"
cat >"$workspace/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
[[ "$*" == 'is-active --quiet mdatp' || "$*" == 'is-active --quiet himmelblaud' || "$*" == 'is-active --quiet himmelblaud-tasks' ]] || exit 99
[[ "${TEST_SERVICE_FAILURE:-}" != "${@: -1}" ]]
SYSTEMCTL
cat >"$workspace/bin/mdatp" <<'MDATP'
#!/usr/bin/env bash
[[ "$*" == 'health --output json' ]] || exit 99
case "${TEST_HEALTH:-healthy}" in
    healthy) printf '{"org_id":"12345678-1234-1234-1234-123456789abc","healthy":true,"real_time_protection_enabled":true}\n' ;;
    unhealthy) printf '{"org_id":"12345678-1234-1234-1234-123456789abc","healthy":false,"real_time_protection_enabled":true}\n' ;;
    protection-off) printf '{"org_id":"12345678-1234-1234-1234-123456789abc","healthy":true,"real_time_protection_enabled":false}\n' ;;
    not-onboarded) printf '{"org_id":"","healthy":true,"real_time_protection_enabled":true}\n' ;;
    invalid-json) printf 'unavailable\n' ;;
    unavailable) exit 1 ;;
    *) exit 99 ;;
esac
MDATP
cat >"$workspace/bin/snap" <<'SNAP'
#!/usr/bin/env bash
case "$*" in
    'list thunderbird')
        if [[ "${TEST_SNAP_FAILURE:-}" == true ]]; then
            printf 'error: cannot communicate with snapd\n' >&2
            exit 1
        fi
        printf 'thunderbird installed\n'
        ;;
    'list rhythmbox'|'list remmina'|'list shotwell')
        printf 'error: no matching snaps installed\n' >&2
        exit 1
        ;;
    'remove --purge thunderbird') printf '%s\n' "$*" >>"$TEST_SNAP_LOG" ;;
    *) exit 99 ;;
esac
SNAP
chmod 0700 "$workspace/bin/systemctl" "$workspace/bin/mdatp" "$workspace/bin/snap"
unshare --user --map-root-user --mount --fork bash -s -- "$workspace/bin" "$payload_directory/verify-first-boot.sh" "$payload_directory/cleanup-desktop-apps.sh" <<'READINESS'
set -euo pipefail
mount --make-rprivate /
mount -t tmpfs -o size=1m tmpfs /var/lib
export PATH="$1:$PATH"
readiness_script="$2"
expect_failure() {
    if bash "$readiness_script"; then
        printf 'FAIL: readiness unexpectedly succeeded.\n' >&2
        exit 1
    fi
    [[ ! -f /var/lib/linux-onboarding/ready ]]
}
for health in unhealthy protection-off not-onboarded invalid-json unavailable; do
    export TEST_HEALTH="$health"
    expect_failure
done
export TEST_HEALTH=healthy
for service in mdatp himmelblaud himmelblaud-tasks; do
    export TEST_SERVICE_FAILURE="$service"
    expect_failure
done
unset TEST_SERVICE_FAILURE
bash "$readiness_script"
[[ -f /var/lib/linux-onboarding/ready ]]
export TEST_HEALTH=unavailable
bash "$readiness_script"
printf 'PASS: failed readiness leaves no success marker; a later healthy check succeeds and completed setup is idempotent.\n'
export TEST_SNAP_FAILURE=true TEST_SNAP_LOG=/var/lib/snap-removal.log
if bash "$3" --snaps; then
    printf 'FAIL: Snap cleanup ignored a snapd communication error.\n' >&2
    exit 1
fi
[[ ! -f /var/lib/linux-onboarding/desktop-apps-removed ]]
unset TEST_SNAP_FAILURE
bash "$3" --snaps
[[ -f /var/lib/linux-onboarding/desktop-apps-removed ]]
[[ "$(cat "$TEST_SNAP_LOG")" == 'remove --purge thunderbird' ]]
export TEST_SNAP_FAILURE=true
bash "$3" --snaps
printf 'PASS: Snap cleanup retries daemon errors, removes only the selected installed Snap, and is idempotent.\n'
READINESS

printf '%%himmelblau-users ALL=(ALL:ALL) ALL\n' >"$workspace/sudo-policy"
visudo -cf "$workspace/sudo-policy"
grep -Fq "printf '%%himmelblau-users ALL=(ALL:ALL) ALL\\n'" "$script_directory/onboard-linux.sh"
grep -Fq 'optional pam_exec.so quiet seteuid type=open_session /usr/local/sbin/linux-device-name --first-login' "$script_directory/onboard-linux.sh"
! grep -q NOPASSWD "$workspace/sudo-policy"
printf 'PASS: the Entra group sudo policy validates and does not grant passwordless sudo.\n'

unshare --user --map-root-user --mount --fork bash -s -- "$payload_directory/configure-device-name.sh" <<'DEVICE_NAME'
set -euo pipefail
umask 077
awk_executable="$(readlink -f "$(command -v awk)")"
mount --make-rprivate /
mount -t tmpfs -o size=1m tmpfs /etc
mount -t tmpfs -o size=1m tmpfs /var/lib
printf '127.0.0.1 localhost\n127.0.1.1 localhost\n::1 localhost ip6-localhost\n' >/etc/hosts
source "$1"
awk() { "$awk_executable" "$@"; }
getent() {
    printf '%s:x:%s:6000000:%s:/home/test:/bin/bash\n' "$PAM_USER" "${TEST_USER_UID:-6000001}" "${TEST_DISPLAY_NAME:-Taylor Morgan}"
}
hostnamectl() {
    [[ "$1" == set-hostname ]]
    [[ "${TEST_RENAME_FAILURE:-}" != true ]] || return 1
    printf '%s\n' "$2" >>/var/lib/hostname-calls
}
timeout() {
    [[ "$1" == 5s || "$1" == 15s ]]
    shift
    "$@"
}
logger() { return 0; }
(configure_device_name --initial)
initial_name="$(cat /etc/hostname)"
[[ "$initial_name" =~ ^ubuntu-[a-f0-9]{8}$ ]]
grep -Fxq 'preserve_hostname: true' /etc/cloud/cloud.cfg.d/99-linux-onboarding-hostname.cfg
(configure_device_name --initial)
[[ "$(cat /etc/hostname)" == "$initial_name" ]]
export PAM_TYPE=open_session PAM_USER=taylor.morgan@example.com PAM_SERVICE=sudo
(configure_device_name --first-login)
[[ ! -e /var/lib/hostname-calls ]]
export PAM_SERVICE=gdm-password TEST_USER_UID=1000
(configure_device_name --first-login)
[[ ! -e /var/lib/hostname-calls ]]
export TEST_USER_UID=6000001 TEST_RENAME_FAILURE=true
if (configure_device_name --first-login); then
    printf 'FAIL: the first-login helper ignored a hostnamectl failure.\n' >&2
    exit 1
fi
[[ ! -f /var/lib/linux-onboarding/hostname-set ]]
unset TEST_RENAME_FAILURE
(configure_device_name --first-login)
expected_name="ubuntu-taylor-${initial_name#ubuntu-}"
[[ "$(cat /etc/hostname)" == "$expected_name" ]]
[[ "$(cat /var/lib/linux-onboarding/hostname-set)" == "$expected_name" ]]
grep -Fxq "127.0.1.1$(printf '\t')$expected_name" /etc/hosts
grep -Fxq '127.0.0.1 localhost' /etc/hosts
[[ "$(stat -c %a /etc/hostname)" == 644 ]]
export PAM_USER=alex.smith@example.com TEST_DISPLAY_NAME='Alex Smith'
(configure_device_name --first-login)
[[ "$(wc -l </var/lib/hostname-calls)" -eq 1 ]]
[[ "$(cat /etc/hostname)" == "$expected_name" ]]
[[ "$(device_name_for_account '' alex.smith@example.com 12345678123412341234123456789abc)" == ubuntu-alex-12345678 ]]
[[ "$(device_name_for_account 'Oyvind Nordmann' user@example.com 12345678123412341234123456789abc)" == ubuntu-oyvind-12345678 ]]
[[ "$(device_name_for_account $'\303\230yvind Nordmann' user@example.com 12345678123412341234123456789abc)" == ubuntu-oyvind-12345678 ]]
[[ "$(device_name_for_account '---' user@example.com 12345678123412341234123456789abc)" == ubuntu-user-12345678 ]]
if device_name_for_account Taylor user@example.com invalid-identifier; then
    printf 'FAIL: hostname generation accepted an invalid device identifier.\n' >&2
    exit 1
fi
printf 'PASS: unique pre-enrollment naming, first-login rename, failure retry, non-Entra exclusion, sudo-session exclusion, hosts preservation, and one-time behavior validate.\n'
DEVICE_NAME

source "$payload_directory/configure-desktop-defaults.sh"
for architecture in amd64 arm64; do
    desktop_root="$workspace/desktop-$architecture"
    schema_directory="$desktop_root/usr/share/glib-2.0/schemas"
    mkdir -p "$schema_directory" "$desktop_root/usr/share/applications"
    cat >"$schema_directory/org.gnome.shell.gschema.xml" <<'SCHEMA'
<schemalist>
  <schema id="org.gnome.shell" path="/org/gnome/shell/">
    <key name="favorite-apps" type="as"><default>[]</default></key>
  </schema>
</schemalist>
SCHEMA
    if [[ "$architecture" == amd64 ]]; then
        if configure_desktop_defaults "$desktop_root" "$architecture"; then
            printf 'FAIL: desktop setup accepted a missing Edge launcher.\n' >&2
            exit 1
        fi
        touch "$desktop_root/usr/share/applications/microsoft-edge.desktop"
    fi
    configure_desktop_defaults "$desktop_root" "$architecture"
    configure_desktop_defaults "$desktop_root" "$architecture"
    [[ "$(readlink "$desktop_root/etc/systemd/user/gnome-initial-setup-first-login.service")" == /dev/null ]]
    [[ "$(readlink "$desktop_root/etc/systemd/user/gnome-initial-setup-upgrade-login.service")" == /dev/null ]]
    grep -Fxq Hidden=true "$desktop_root/etc/xdg/autostart/gnome-initial-setup-first-login.desktop"
    for desktop_session in GNOME ubuntu:GNOME; do
        favorites="$(GSETTINGS_BACKEND=memory XDG_CURRENT_DESKTOP="$desktop_session" gsettings --schemadir "$schema_directory" get org.gnome.shell favorite-apps)"
        [[ "$favorites" != *libreoffice-writer* && "$favorites" != *thunderbird* && "$favorites" != *Rhythmbox* ]]
        [[ "$favorites" == *org.gnome.Nautilus.desktop* && "$favorites" == *snap-store_snap-store.desktop* && "$favorites" == *org.gnome.Yelp.desktop* ]]
        if [[ "$architecture" == amd64 ]]; then
            [[ "$favorites" == *microsoft-edge.desktop* && "$favorites" != *firefox* ]]
        else
            [[ "$favorites" == *firefox_firefox.desktop* && "$favorites" != *microsoft-edge* ]]
        fi
        [[ "$(GSETTINGS_BACKEND=memory XDG_CURRENT_DESKTOP="$desktop_session" gsettings --schemadir "$schema_directory" writable org.gnome.shell favorite-apps)" == true ]]
    done
done
printf 'PASS: automatic Welcome is disabled; compiled dock defaults exclude Writer, select the available browser, preserve other standard pins, and remain customizable.\n'