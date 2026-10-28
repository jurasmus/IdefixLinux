#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compliance_script="$script_directory/compliance.sh"
if [[ ! -f "$compliance_script" ]]; then
    compliance_script="$script_directory/../compliance/compliance.sh"
fi

HIMMELBLAU_DOMAIN=""
MDE_ONBOARDING_FILE=""
INSTALL_HIMMELBLAU=true
INSTALL_ONLY=false
PACKAGE_DIRECTORY=""

usage() {
    cat <<'EOF'
Usage: sudo ./onboard-linux.sh --mde-onboarding-file FILE [options]

Options:
  --himmelblau-domain DOMAIN       Entra sign-in domain (required unless skipped)
  --skip-himmelblau                Install Defender only
    --install-only                   Configure an installer target without starting services
    --package-directory DIRECTORY    Use verified local packages without repository access
  -h, --help                       Show this help
EOF
}

log() {
    printf '[onboard-linux] %s\n' "$*"
}

die() {
    printf '[onboard-linux] ERROR: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mde-onboarding-file)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            MDE_ONBOARDING_FILE="$2"
            shift 2
            ;;
        --himmelblau-domain)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            HIMMELBLAU_DOMAIN="$2"
            shift 2
            ;;
        --skip-himmelblau)
            INSTALL_HIMMELBLAU=false
            shift
            ;;
        --install-only)
            INSTALL_ONLY=true
            shift
            ;;
        --package-directory)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            PACKAGE_DIRECTORY="$(realpath -- "$2")"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Run this script with sudo."
[[ -r "$compliance_script" ]] || die "Missing compliance script; retain the repository layout or place compliance.sh beside this script."
[[ -r "$MDE_ONBOARDING_FILE" ]] || die "Provide a readable Defender onboarding JSON file."
if [[ "$INSTALL_HIMMELBLAU" == true && -z "$HIMMELBLAU_DOMAIN" ]]; then
    die "--himmelblau-domain is required unless --skip-himmelblau is used."
fi

source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This example supports Ubuntu only."
[[ "${VERSION_ID:-}" == "26.04" ]] || die "This example supports Ubuntu 26.04 only."
architecture="$(dpkg --print-architecture)"
case "$architecture" in
    amd64|arm64) ;;
    *) die "This example supports amd64 and arm64 only (detected: $architecture)." ;;
esac
command -v systemctl >/dev/null || die "systemd is required."

export DEBIAN_FRONTEND=noninteractive
if [[ -n "$PACKAGE_DIRECTORY" ]]; then
    [[ -f "$PACKAGE_DIRECTORY/SHA256SUMS" ]] || die "Missing package checksums."
    [[ "$(cat "$PACKAGE_DIRECTORY/architecture")" == "$architecture" ]] || die "Package bundle architecture does not match this system."
    log "Verifying offline package bundle"
    (cd -- "$PACKAGE_DIRECTORY" && sha256sum --check SHA256SUMS)
    log "Installing bundled packages without downloads"
    printf 'code code/add-microsoft-repo boolean false\n' | debconf-set-selections
    bash "$(dirname -- "${BASH_SOURCE[0]}")/install-offline-packages.sh" "$PACKAGE_DIRECTORY"
    install -d -m 0755 /etc/apt/keyrings
    install -m 0644 "$PACKAGE_DIRECTORY/microsoft.asc" /etc/apt/keyrings/microsoft-defender.asc
    install -m 0644 "$PACKAGE_DIRECTORY/microsoft-apps.asc" /etc/apt/keyrings/microsoft-apps.asc
else
    log "Installing prerequisites"
    apt-get update
    apt-get install -y ca-certificates curl jq libplist-utils
    install -d -m 0755 /etc/apt/keyrings

    log "Installing Microsoft Defender for Endpoint"
    curl --fail --silent --show-error --location \
        https://packages.microsoft.com/keys/microsoft-2025.asc \
        --output /etc/apt/keyrings/microsoft-defender.asc
    chmod 0644 /etc/apt/keyrings/microsoft-defender.asc
fi
cat >/etc/apt/sources.list.d/microsoft-defender.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/ubuntu/${VERSION_ID}/prod
Suites: ${VERSION_CODENAME}
Components: main
Architectures: ${architecture}
Signed-By: /etc/apt/keyrings/microsoft-defender.asc
EOF
if [[ -n "$PACKAGE_DIRECTORY" ]]; then
    cat >/etc/apt/sources.list.d/vscode.list <<EOF
deb [arch=${architecture} signed-by=/etc/apt/keyrings/microsoft-apps.asc] https://packages.microsoft.com/repos/code stable main
EOF
    if [[ "$architecture" == amd64 ]]; then
        cat >/etc/apt/sources.list.d/microsoft-edge.sources <<'EOF'
    Types: deb
    URIs: https://packages.microsoft.com/repos/edge
    Suites: stable
    Components: main
    Architectures: amd64
    Signed-By: /etc/apt/keyrings/microsoft-apps.asc
EOF
        rm -f /etc/apt/sources.list.d/microsoft-edge.list /etc/apt/sources.list.d/microsoft-edge-stable.list
    else
        log "ARM64 includes VS Code; official Edge and Intune Portal packages are unavailable."
    fi
fi
if [[ -z "$PACKAGE_DIRECTORY" ]]; then
    apt-get update
    apt-get install -y mdatp
fi

install -d -m 0755 /usr/local/bin
install -o root -g root -m 0755 "$compliance_script" /usr/local/bin/managed-compliance

install -d -m 0755 /etc/opt/microsoft/mdatp/managed
install -m 0600 "$MDE_ONBOARDING_FILE" /etc/opt/microsoft/mdatp/mdatp_onboard.json
cat >/etc/opt/microsoft/mdatp/managed/mdatp_managed.json <<'EOF'
{
  "antivirusEngine": {
    "enforcementLevel": "real_time",
    "behaviorMonitoring": "enabled"
  },
  "cloudService": {
    "enabled": true,
    "automaticDefinitionUpdateEnabled": true
  }
}
EOF
chmod 0644 /etc/opt/microsoft/mdatp/managed/mdatp_managed.json
systemctl enable mdatp
if [[ "$INSTALL_ONLY" == false ]]; then
    systemctl restart mdatp
fi

if [[ "$INSTALL_HIMMELBLAU" == true ]]; then
    log "Installing Himmelblau Community Nightly"
    getent group himmelblau-users >/dev/null || groupadd --system himmelblau-users
    command -v sudo >/dev/null || die "The Ubuntu Desktop sudo package is required."
    command -v visudo >/dev/null || die "visudo is required to validate local administrator access."
    sudo_policy="$(mktemp)"
    printf '%%himmelblau-users ALL=(ALL:ALL) ALL\n' >"$sudo_policy"
    if ! visudo -cf "$sudo_policy"; then
        rm -f -- "$sudo_policy"
        die "The Entra sudo policy did not pass validation."
    fi
    install -d -m 0750 /etc/sudoers.d
    install -m 0440 "$sudo_policy" /etc/sudoers.d/90-himmelblau-users
    rm -f -- "$sudo_policy"
    visudo -c
    install -m 0755 "$(dirname -- "${BASH_SOURCE[0]}")/configure-device-name.sh" /usr/local/sbin/linux-device-name
    cat >/usr/share/pam-configs/linux-device-name <<'EOF'
Name: Name the device after its first successful Entra login
Default: yes
Priority: 0
Session-Type: Additional
Session:
        optional pam_exec.so quiet seteuid type=open_session /usr/local/sbin/linux-device-name --first-login
EOF
    install -d -m 0755 /etc/himmelblau
    touch /etc/himmelblau/user-map
    chmod 0644 /etc/himmelblau/user-map

    cat >/etc/himmelblau/himmelblau.conf <<EOF
[global]
domain = ${HIMMELBLAU_DOMAIN}
apply_policy = true
enable_hello = true
enable_experimental_mfa = true
hello_pin_min_length = 6
home_prefix = /home/
home_attr = CN
home_alias = CN
use_etc_skel = true
shell = /bin/bash
cn_name_mapping = false
user_map_file = /etc/himmelblau/user-map
id_attr_map = name
idmap_range = 6000000-6999999
local_groups = himmelblau-users
debug = false
EOF
    chmod 0644 /etc/himmelblau/himmelblau.conf

    if [[ -z "$PACKAGE_DIRECTORY" ]]; then
        installer_script="$(mktemp)"
        trap 'rm -f -- "$installer_script"' EXIT
        curl --fail --silent --show-error --location \
            https://himmelblau-idm.org/install --output "$installer_script"
        sh "$installer_script" --channel nightly
        rm -f -- "$installer_script"
        trap - EXIT

        packages=(himmelblau himmelblau-broker pam-himmelblau nss-himmelblau himmelblau-sso himmelblau-sso-policies himmelblau-sshd-config himmelblau-apparmor o365)
        apt-get install -y "${packages[@]}"
    fi

    pam-auth-update --enable "Azure Entra Id authentication"
    pam-auth-update --enable linux-device-name
    for database in passwd group; do
        if ! grep -Eq "^${database}:.*(^|[[:space:]])himmelblau([[:space:]]|$)" /etc/nsswitch.conf; then
            sed -i -E "s/^(${database}:.*)$/\1 himmelblau/" /etc/nsswitch.conf
        fi
    done
    systemctl enable himmelblaud.service himmelblaud-tasks.service himmelblau-hsm-pin-init.service
    if [[ "$INSTALL_ONLY" == false ]]; then
        systemctl start himmelblaud.service himmelblaud-tasks.service
    fi
fi

if [[ "$INSTALL_ONLY" == true ]]; then
    log "Packages configured. Services will start on the installed system's next boot."
    exit 0
fi

log "Waiting for Defender health information"
for _ in {1..30}; do
    org_id="$(mdatp health --field org_id 2>/dev/null || true)"
    [[ "$org_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] && break
    sleep 2
done

mdatp health --field org_id || true
mdatp health --field healthy || true
if [[ "$INSTALL_HIMMELBLAU" == true ]]; then
    log "Restart, then sign in once with a full Entra UPN to complete Intune enrollment."
else
    log "Defender setup complete; Himmelblau and Intune enrollment were skipped."
fi