#!/usr/bin/env bash
set -euo pipefail
umask 077

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compliance_directory="$(cd -- "$script_directory/../compliance" && pwd)"
input_iso=""
output_iso=""
onboarding_file=""
domain=""
package_directory=""

usage() {
    cat <<'EOF'
Usage: bash build-onboarding-iso.sh --iso FILE --output FILE \
  --mde-onboarding-file FILE --himmelblau-domain DOMAIN [options]

Options:
  --package-directory DIRECTORY    Reuse a previously prepared package bundle
  -h, --help                       Show help

Run on Ubuntu/WSL with xorriso, squashfs-tools, jq, curl, apt, and ubuntu-keyring installed.
No sudo is needed to build. Packages are downloaded and embedded at build time.
Input must be an official Ubuntu 26.04 Desktop amd64 or arm64 ISO.
Network, disk, and encryption choices remain interactive; no local user is created.
OS installation is offline. Internet is required for first Entra sign-in.
The output contains tenant-specific Defender onboarding data; keep it private.
EOF
}

die() {
    printf '[iso-builder] ERROR: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso|--output|--mde-onboarding-file|--himmelblau-domain|--package-directory)
            [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value."
            case "$1" in
                --iso) input_iso="$2" ;;
                --output) output_iso="$2" ;;
                --mde-onboarding-file) onboarding_file="$2" ;;
                --himmelblau-domain) domain="$2" ;;
                --package-directory) package_directory="$2" ;;
            esac
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

for dependency in xorriso unsquashfs jq realpath md5sum sha256sum sed find sort; do
    command -v "$dependency" >/dev/null || die "Install the required command: $dependency"
done
[[ -f "$input_iso" && -r "$input_iso" ]] || die "Provide a readable --iso file."
[[ -n "$output_iso" ]] || die "Provide --output."
[[ -f "$onboarding_file" && -r "$onboarding_file" ]] || die "Provide a readable --mde-onboarding-file."
[[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && "$domain" == *.* ]] || die "Provide a DNS domain such as contoso.com."
jq -e 'type == "object" and length > 0' "$onboarding_file" >/dev/null || die "The Defender onboarding file must be a nonempty JSON object."
for payload in onboard-linux.sh verify-first-boot.sh prepare-onboarding-packages.sh install-offline-packages.sh cleanup-desktop-apps.sh configure-device-name.sh configure-desktop-defaults.sh; do
    [[ -f "$script_directory/$payload" ]] || die "Missing sibling file: $payload"
done
[[ -f "$compliance_directory/compliance.sh" ]] || die "Missing compliance/compliance.sh."

input_iso="$(realpath -- "$input_iso")"
output_iso="$(realpath -m -- "$output_iso")"
[[ "$input_iso" != "$output_iso" ]] || die "Input and output must be different files."
[[ ! -e "$output_iso" && ! -L "$output_iso" ]] || die "Output already exists; choose a new filename."
[[ -d "$(dirname -- "$output_iso")" ]] || die "The output directory must already exist."
work_directory="$(mktemp -d "$(dirname -- "$output_iso")/.ubuntu-onboarding.XXXXXX")"
trap 'rm -rf -- "$work_directory"' EXIT
iso_tree="$work_directory/tree"

printf '[iso-builder] Reading ISO metadata and boot configuration.\n'
install -d -m 0755 "$iso_tree/boot/grub"
xorriso -abort_on FAILURE -osirrox on -indev "$input_iso" \
  -extract /.disk/info "$work_directory/disk-info" \
  -extract /casper/install-sources.yaml "$work_directory/install-sources.yaml" \
  -extract /md5sum.txt "$work_directory/source-md5sum.txt" \
  -extract /boot/grub/grub.cfg "$iso_tree/boot/grub/grub.cfg"
chmod -R u+w "$iso_tree"
[[ -f "$work_directory/disk-info" ]] || die "Missing Ubuntu media identification."
disk_info="$(<"$work_directory/disk-info")"
[[ "$disk_info" =~ Ubuntu.*26[.]04([.][0-9]+)?[[:space:]].*[[:space:]](amd64|arm64)([[:space:]]|$) ]] || die "Only Ubuntu 26.04 amd64 or arm64 media is supported."
iso_architecture="${BASH_REMATCH[2]}"
printf '[iso-builder] Detected Ubuntu 26.04 %s media.\n' "$iso_architecture"
[[ -f "$work_directory/install-sources.yaml" ]] || die "Missing Ubuntu installation sources."
grep -Eq 'id: *ubuntu-desktop(-minimal)?[[:space:]]*$' "$work_directory/install-sources.yaml" || die "Use Ubuntu Desktop, not Server or a flavor ISO."
[[ -f "$iso_tree/boot/grub/grub.cfg" ]] || die "Missing GRUB configuration."
if grep -Eq '  \./autoinstall\.yaml$|  \./onboarding/' "$work_directory/source-md5sum.txt"; then
  die "The ISO already contains custom provisioning files. Use an unmodified Ubuntu ISO."
fi
if grep -Fq '  ./boot/grub/loopback.cfg' "$work_directory/source-md5sum.txt"; then
  xorriso -abort_on FAILURE -osirrox on -indev "$input_iso" \
    -extract /boot/grub/loopback.cfg "$iso_tree/boot/grub/loopback.cfg"
fi

payload_directory="$iso_tree/onboarding"
install -d -m 0700 "$payload_directory"
install -m 0700 "$script_directory/onboard-linux.sh" "$script_directory/verify-first-boot.sh" "$compliance_directory/compliance.sh" "$script_directory/install-offline-packages.sh" "$payload_directory/"
install -m 0700 "$script_directory/cleanup-desktop-apps.sh" "$payload_directory/"
install -m 0700 "$script_directory/configure-device-name.sh" "$payload_directory/"
install -m 0700 "$script_directory/configure-desktop-defaults.sh" "$payload_directory/"
sed -i 's/\r$//' "$payload_directory/"*.sh
install -m 0600 "$onboarding_file" "$payload_directory/defender-onboarding.json"
printf 'domain=%q\n' "$domain" >"$payload_directory/settings.sh"

if [[ -z "$package_directory" ]]; then
  package_directory="$work_directory/packages"
  bash "$script_directory/prepare-onboarding-packages.sh" \
    --architecture "$iso_architecture" --output "$package_directory"
fi
package_directory="$(realpath -- "$package_directory")"
[[ -f "$package_directory/SHA256SUMS" ]] || die "Missing offline package checksums."
[[ "$(cat "$package_directory/architecture")" == "$iso_architecture" ]] || die "Package bundle does not match the ISO architecture."
(cd -- "$package_directory" && sha256sum --check SHA256SUMS) || die "Package bundle verification failed."
[[ -f "$package_directory/microsoft-apps.asc" ]] || die "Prepare a new bundle containing Microsoft desktop applications and their signing key."
required_apps=(code)
if [[ "$iso_architecture" == amd64 ]]; then
  required_apps+=(microsoft-edge-stable intune-portal)
fi
for application in "${required_apps[@]}"; do
  grep -Fxq "$application" "$package_directory/package-names" || die "Prepare a new bundle containing $application."
done
printf '[iso-builder] Validating offline packages against the source Desktop package database.\n'
xorriso -abort_on FAILURE -osirrox on -indev "$input_iso" \
  -extract /casper/minimal.standard.squashfs "$work_directory/desktop.squashfs"
unsquashfs -cat "$work_directory/desktop.squashfs" var/lib/dpkg/status >"$work_directory/target-status"
[[ -s "$work_directory/target-status" ]] || die "Missing source Desktop package database."
if ! bash "$script_directory/cleanup-desktop-apps.sh" --simulate "$work_directory/target-status" \
  >"$work_directory/removal-validation.log" 2>&1; then
  cat "$work_directory/removal-validation.log" >&2
  die "Desktop application removal cannot be applied safely to the source image."
fi
printf 'Dir::State::status "%s";\n' "$work_directory/target-status" >"$work_directory/target-apt.conf"
if ! APT_CONFIG="$work_directory/target-apt.conf" bash "$script_directory/install-offline-packages.sh" \
  "$package_directory" --simulate >"$work_directory/target-validation.log" 2>&1; then
  cat "$work_directory/target-validation.log" >&2
  die "Offline packages cannot be installed on the source Desktop image."
fi
rm -f -- "$work_directory/desktop.squashfs"
install -d -m 0700 "$payload_directory/packages"
cp -a -- "$package_directory/." "$payload_directory/packages/"

cat >"$payload_directory/install-target.sh" <<'INSTALL_TARGET'
#!/usr/bin/env bash
set -euo pipefail
cleanup_target_secrets() {
  rm -f /target/opt/linux-onboarding/defender-onboarding.json \
    /target/opt/linux-onboarding/settings.sh
  rm -rf /target/opt/linux-onboarding/packages
}
trap cleanup_target_secrets EXIT
source /cdrom/onboarding/settings.sh
install -d -m 0700 /target/opt/linux-onboarding
install -m 0700 /cdrom/onboarding/*.sh /target/opt/linux-onboarding/
install -m 0600 /cdrom/onboarding/defender-onboarding.json /target/opt/linux-onboarding/
cp -a /cdrom/onboarding/packages /target/opt/linux-onboarding/
install -m 0600 /cdrom/onboarding/packages/versions.tsv /target/opt/linux-onboarding/package-versions.tsv
arguments=(--install-only --mde-onboarding-file /opt/linux-onboarding/defender-onboarding.json
  --himmelblau-domain "$domain" --package-directory /opt/linux-onboarding/packages)
curtin in-target -- bash /opt/linux-onboarding/onboard-linux.sh "${arguments[@]}"
curtin in-target -- bash /opt/linux-onboarding/configure-device-name.sh --initial
curtin in-target -- bash /opt/linux-onboarding/cleanup-desktop-apps.sh --packages
curtin in-target -- bash /opt/linux-onboarding/configure-desktop-defaults.sh
install -m 0644 /cdrom/onboarding/linux-desktop-cleanup.service /cdrom/onboarding/linux-desktop-cleanup.timer /target/etc/systemd/system/
curtin in-target -- systemctl enable linux-desktop-cleanup.timer
install -m 0644 /cdrom/onboarding/linux-onboarding-ready.service /target/etc/systemd/system/
install -d -m 0755 /target/etc/systemd/system/display-manager.service.d
install -m 0644 /cdrom/onboarding/gdm-onboarding.conf /target/etc/systemd/system/display-manager.service.d/onboarding.conf
install -m 0644 /cdrom/onboarding/linux-onboarding-ready.timer /target/etc/systemd/system/
curtin in-target -- systemctl enable linux-onboarding-ready.timer gdm.service
curtin in-target -- systemctl set-default graphical.target
install -d -m 0755 /target/etc/gdm3
printf '[daemon]\nInitialSetupEnable=false\n' >/target/etc/gdm3/custom.conf
install -d -m 0755 /target/etc/dconf/db/gdm.d /target/etc/dconf/profile
if [[ ! -f /target/etc/dconf/profile/gdm ]]; then
    printf 'user-db:user\nsystem-db:gdm\nfile-db:/usr/share/gdm/greeter-dconf-defaults\n' >/target/etc/dconf/profile/gdm
fi
printf '[org/gnome/login-screen]\ndisable-user-list=false\n' >/target/etc/dconf/db/gdm.d/01-entra-login
curtin in-target -- dconf update
INSTALL_TARGET

cat >"$payload_directory/linux-onboarding-ready.service" <<'SERVICE'
[Unit]
Description=Check initial Defender and Himmelblau readiness without blocking sign-in
After=mdatp.service himmelblaud.service himmelblaud-tasks.service
ConditionPathExists=!/var/lib/linux-onboarding/ready

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/linux-onboarding/verify-first-boot.sh
TimeoutStartSec=45
SERVICE

cat >"$payload_directory/linux-onboarding-ready.timer" <<'TIMER'
[Unit]
Description=Retry initial Defender and Himmelblau readiness checks

[Timer]
OnBootSec=30s
OnUnitInactiveSec=2min
Unit=linux-onboarding-ready.service

[Install]
WantedBy=timers.target
TIMER

cat >"$payload_directory/gdm-onboarding.conf" <<'GDM'
[Unit]
Wants=himmelblaud.service himmelblaud-tasks.service
After=himmelblaud.service himmelblaud-tasks.service
GDM

cat >"$payload_directory/linux-desktop-cleanup.service" <<'SERVICE'
[Unit]
Description=Remove selected preinstalled Snap applications without blocking sign-in
Wants=snapd.service
After=snapd.service
ConditionPathExists=!/var/lib/linux-onboarding/desktop-apps-removed

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/linux-onboarding/cleanup-desktop-apps.sh --snaps
TimeoutStartSec=360
SERVICE

cat >"$payload_directory/linux-desktop-cleanup.timer" <<'TIMER'
[Unit]
Description=Retry selected desktop Snap application cleanup

[Timer]
OnBootSec=15s
OnUnitInactiveSec=2min
Unit=linux-desktop-cleanup.service

[Install]
WantedBy=timers.target
TIMER

cat >"$iso_tree/autoinstall.yaml" <<'AUTOINSTALL'
autoinstall:
  version: 1
  refresh-installer:
    update: false
  interactive-sections:
    - locale
    - keyboard
    - network
    - storage
  source:
    id: ubuntu-desktop
    search_drivers: false
  user-data:
    users: []
  apt:
    mirror-selection:
      primary: []
    fallback: offline-install
    geoip: false
  drivers:
    install: false
  oem:
    install: false
  late-commands:
    - bash /cdrom/onboarding/install-target.sh
  shutdown: reboot
AUTOINSTALL

for grub_config in "$iso_tree/boot/grub/grub.cfg" "$iso_tree/boot/grub/loopback.cfg"; do
    [[ -f "$grub_config" ]] || continue
    sed -i -E '/^[[:space:]]*linux[[:space:]].*\/casper\/vmlinuz/ { /(^|[[:space:]])autoinstall([[:space:]]|$)/! s@[[:space:]]+---@ autoinstall ---@; }' "$grub_config"
done
grep -Eq '^[[:space:]]*linux[[:space:]].*/casper/vmlinuz.*[[:space:]]autoinstall([[:space:]]|$)' \
    "$iso_tree/boot/grub/grub.cfg" || die "Could not add autoinstall to the ISO's boot entry."

printf '[iso-builder] Updating checksums for changed and added files.\n'
grep -Ev '  \./(autoinstall\.yaml|boot/grub/grub\.cfg|boot/grub/loopback\.cfg|onboarding/)' \
  "$work_directory/source-md5sum.txt" >"$iso_tree/md5sum.txt"
(
    cd -- "$iso_tree"
  find . -type f ! -path './md5sum.txt' -print0 |
    LC_ALL=C sort -z | xargs -0 -r md5sum >>"$iso_tree/md5sum.txt"
)
xorriso_args=(
  -abort_on FAILURE
  -indev "$input_iso"
  -outdev "$work_directory/custom.iso"
  -overwrite on
  -map "$iso_tree/autoinstall.yaml" /autoinstall.yaml
  -map "$iso_tree/boot/grub/grub.cfg" /boot/grub/grub.cfg
  -map "$iso_tree/md5sum.txt" /md5sum.txt
  -map "$payload_directory" /onboarding
)
if [[ -f "$iso_tree/boot/grub/loopback.cfg" ]]; then
  xorriso_args+=(-map "$iso_tree/boot/grub/loopback.cfg" /boot/grub/loopback.cfg)
fi
xorriso "${xorriso_args[@]}" -boot_image any replay -commit -end
chmod 0600 "$work_directory/custom.iso"
ln -- "$work_directory/custom.iso" "$output_iso"
sha256sum -- "$output_iso"
printf '[iso-builder] Created %s\n' "$output_iso"
printf '[iso-builder] Keep this ISO private. It contains tenant-specific Defender onboarding data.\n'
printf '[iso-builder] Defender and Himmelblau packages are embedded; OS installation needs no repository access.\n'
printf '[iso-builder] Internet is still required for first Entra sign-in and cloud enrollment.\n'