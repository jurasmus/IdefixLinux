#!/usr/bin/env bash
set -euo pipefail
umask 077

architecture=""
output_directory=""
nightly_build="2026-10-24-2ad5a39cf571"
himmelblau_version="5.0.0-ubuntu26.04~20261024"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --architecture|--output|--himmelblau-build|--himmelblau-version)
            [[ $# -ge 2 && -n "$2" ]] || { printf 'Missing value for %s\n' "$1" >&2; exit 1; }
            case "$1" in
                --architecture) architecture="$2" ;;
                --output) output_directory="$2" ;;
                --himmelblau-build) nightly_build="$2" ;;
                --himmelblau-version) himmelblau_version="$2" ;;
            esac
            shift 2
            ;;
        -h|--help)
            printf 'Usage: bash prepare-onboarding-packages.sh --architecture amd64|arm64 --output DIRECTORY [--himmelblau-build DATE-COMMIT --himmelblau-version VERSION]\n'
            exit 0
            ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done
[[ "$architecture" == amd64 || "$architecture" == arm64 ]] || { printf 'Choose amd64 or arm64.\n' >&2; exit 1; }
[[ "$nightly_build" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-f0-9]+$ ]] || { printf 'Invalid Nightly build identifier.\n' >&2; exit 1; }
[[ "$himmelblau_version" =~ ^[0-9][a-zA-Z0-9.+~:-]*$ ]] || { printf 'Invalid Himmelblau package version.\n' >&2; exit 1; }
[[ -n "$output_directory" && ! -e "$output_directory" ]] || { printf 'Choose a new output directory.\n' >&2; exit 1; }
for dependency in apt-get curl dpkg-deb sha256sum realpath; do
    command -v "$dependency" >/dev/null || { printf 'Install the required command: %s\n' "$dependency" >&2; exit 1; }
done
ubuntu_keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
[[ -r "$ubuntu_keyring" ]] || { printf 'Install ubuntu-keyring on the build host.\n' >&2; exit 1; }
output_directory="$(realpath -m -- "$output_directory")"
mkdir -p -- "$output_directory"
workspace="$(mktemp -d)"
complete=false
cleanup() {
    rm -rf -- "$workspace"
    if [[ "$complete" == false ]]; then
        rm -rf -- "$output_directory"
    fi
}
trap cleanup EXIT
mkdir -p "$workspace/apt/lists/partial" "$workspace/apt/archives/partial" "$workspace/apt/log" "$workspace/apt/apt.conf.d"
touch "$workspace/apt/status"
curl --fail --silent --show-error --location --retry 3 \
    https://packages.microsoft.com/keys/microsoft-2025.asc --output "$workspace/microsoft.asc"
curl --fail --silent --show-error --location --retry 3 \
    https://packages.microsoft.com/keys/microsoft.asc --output "$workspace/microsoft-apps.asc"
ubuntu_mirror=https://archive.ubuntu.com/ubuntu
ubuntu_security=https://security.ubuntu.com/ubuntu
suffix=""
if [[ "$architecture" == arm64 ]]; then
    ubuntu_mirror=https://ports.ubuntu.com/ubuntu-ports
    ubuntu_security="$ubuntu_mirror"
    suffix=-arm64
fi
cat >"$workspace/apt/sources.list" <<EOF
deb [arch=$architecture signed-by=$ubuntu_keyring] $ubuntu_mirror resolute main restricted universe multiverse
deb [arch=$architecture signed-by=$ubuntu_keyring] $ubuntu_mirror resolute-updates main restricted universe multiverse
deb [arch=$architecture signed-by=$ubuntu_keyring] $ubuntu_security resolute-security main restricted universe multiverse
deb [arch=$architecture signed-by=$workspace/microsoft.asc] https://packages.microsoft.com/ubuntu/26.04/prod resolute main
deb [arch=$architecture signed-by=$workspace/microsoft-apps.asc] https://packages.microsoft.com/repos/code stable main
EOF
if [[ "$architecture" == amd64 ]]; then
    printf 'deb [arch=amd64 signed-by=%s] https://packages.microsoft.com/repos/edge stable main\n' \
        "$workspace/microsoft-apps.asc" >>"$workspace/apt/sources.list"
else
    printf '[package-builder] ARM64 includes VS Code; official Edge and Intune Portal packages are unavailable for this architecture.\n'
fi
cat >"$workspace/apt.conf" <<EOF
Dir::Etc::main "/dev/null";
Dir::Etc::parts "$workspace/apt/apt.conf.d";
Dir::Etc::sourcelist "$workspace/apt/sources.list";
Dir::Etc::sourceparts "-";
Dir::State "$workspace/apt";
Dir::State::status "$workspace/apt/status";
Dir::Cache "$workspace/apt";
Dir::Log "$workspace/apt/log";
APT::Architecture "$architecture";
APT::Architectures { "$architecture"; };
APT::Install-Recommends "false";
APT::Get::List-Cleanup "false";
APT::Update::Error-Mode "any";
Acquire::Retries "3";
Acquire::Languages "none";
EOF
export APT_CONFIG="$workspace/apt.conf"
himmelblau_packages=(himmelblau pam-himmelblau nss-himmelblau himmelblau-sso
    himmelblau-sso-policies himmelblau-sshd-config himmelblau-apparmor o365)
if [[ "$architecture" == arm64 ]]; then
    himmelblau_packages+=(himmelblau-broker)
fi
snapshot_url="https://packages.himmelblau-idm.org/nightly/$nightly_build/deb/ubuntu26.04$suffix"
printf '[package-builder] Downloading pinned Himmelblau Nightly %s over HTTPS (no upstream APT signatures).\n' "$nightly_build"
local_packages=()
for package in "${himmelblau_packages[@]}"; do
    archive="$output_directory/${package}_${himmelblau_version}_${architecture}.deb"
    curl --fail --silent --show-error --location --retry 3 \
        "$snapshot_url/$(basename -- "$archive")" --output "$archive"
    [[ "$(dpkg-deb --field "$archive" Package)" == "$package" && \
       "$(dpkg-deb --field "$archive" Version)" == "$himmelblau_version" && \
       "$(dpkg-deb --field "$archive" Architecture)" == "$architecture" ]] || {
        printf 'Unexpected package metadata: %s\n' "$archive" >&2; exit 1;
    }
    local_packages+=("$archive")
done
packages=(ca-certificates curl jq libplist-utils apparmor dconf-cli dbus libpam-runtime mdatp code)
if [[ "$architecture" == amd64 ]]; then
    packages+=(microsoft-edge-stable intune-portal)
fi
printf '[package-builder] Resolving signed Ubuntu 26.04 %s repositories.\n' "$architecture"
apt-get update
apt-get --download-only install -y "${packages[@]}" "${local_packages[@]}"
shopt -s nullglob
archives=("$workspace/apt/archives/"*.deb)
[[ ${#archives[@]} -gt 0 ]] || { printf 'APT downloaded no packages.\n' >&2; exit 1; }
cp -- "${archives[@]}" "$output_directory/"
install -m 0644 "$workspace/microsoft.asc" "$output_directory/microsoft.asc"
install -m 0644 "$workspace/microsoft-apps.asc" "$output_directory/microsoft-apps.asc"
printf '%s\n' "$architecture" >"$output_directory/architecture"
printf '%s\n' "${packages[@]}" "${himmelblau_packages[@]}" >"$output_directory/package-names"
sed "s|$workspace/||g" "$workspace/apt/sources.list" >"$output_directory/repositories.txt"
printf 'Himmelblau HTTPS snapshot (no upstream APT signatures): %s\n' "$snapshot_url" >>"$output_directory/repositories.txt"
for archive in "$output_directory/"*.deb; do
    dpkg-deb --show --showformat='${Package}\t${Version}\t${Architecture}\n' "$archive"
done | LC_ALL=C sort >"$output_directory/versions.tsv"
(
    cd -- "$output_directory"
    sha256sum -- *.deb architecture microsoft.asc microsoft-apps.asc package-names repositories.txt versions.tsv >SHA256SUMS
)
printf '[package-builder] Checking dependency closure using only the local package repository.\n'
if ! bash "$(dirname -- "${BASH_SOURCE[0]}")/install-offline-packages.sh" "$output_directory" --simulate \
    >"$workspace/offline-validation.log" 2>&1; then
    cat "$workspace/offline-validation.log" >&2
    exit 1
fi
complete=true
printf '[package-builder] Saved %s dependency packages plus %s Himmelblau packages to %s\n' "${#archives[@]}" "${#local_packages[@]}" "$output_directory"