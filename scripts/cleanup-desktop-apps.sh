#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C DEBIAN_FRONTEND=noninteractive

mode="${1:---packages}"
[[ "$mode" == --packages || "$mode" == --snaps || "$mode" == --simulate ]] || {
    printf 'Usage: bash cleanup-desktop-apps.sh --packages|--snaps|--simulate STATUS_FILE\n' >&2
    exit 1
}
[[ "$mode" == --simulate || $EUID -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }
workspace="$(mktemp -d)"
trap 'rm -rf -- "$workspace"' EXIT

if [[ "$mode" == --snaps ]]; then
    marker=/var/lib/linux-onboarding/desktop-apps-removed
    [[ ! -f "$marker" ]] || exit 0
    for application in thunderbird rhythmbox remmina shotwell; do
        if timeout 20s snap list "$application" >"$workspace/snap.log" 2>&1; then
            printf 'Removing Snap application: %s\n' "$application"
            timeout 60s snap remove --purge "$application"
        elif ! grep -Eq '^error: no matching snaps installed|^No snaps are installed yet' "$workspace/snap.log"; then
            cat "$workspace/snap.log" >&2
            printf 'Snap cleanup could not confirm %s is absent; the timer will retry.\n' "$application" >&2
            exit 1
        fi
    done
    install -d -m 0700 /var/lib/linux-onboarding
    touch "$marker"
    exit 0
fi

query_options=()
apt_options=(-o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=-)
if [[ "$mode" == --simulate ]]; then
    [[ -s "${2:-}" ]] || { printf 'Provide a source dpkg status file.\n' >&2; exit 1; }
    mkdir -p "$workspace/dpkg" "$workspace/lists/partial"
    cp -- "$2" "$workspace/dpkg/status"
    query_options+=(--admindir="$workspace/dpkg")
    architecture="$(dpkg-query "${query_options[@]}" -W -f='${Architecture}' dpkg)"
    [[ "$architecture" == amd64 || "$architecture" == arm64 ]]
    apt_options+=(-o "Dir::State::status=$workspace/dpkg/status" -o "Dir::State::lists=$workspace/lists"
        -o "APT::Architecture=$architecture")
fi
mapfile -t packages < <(
    dpkg-query "${query_options[@]}" -W -f='${binary:Package}\t${db:Status-Status}\n' \
        'thunderbird*' 'rhythmbox*' 'remmina*' 'shotwell*' 2>/dev/null |
        awk '$2 == "installed" { print $1 }'
)
[[ ${#packages[@]} -gt 0 ]] || { printf 'No selected Debian applications are installed.\n'; exit 0; }
apt-get "${apt_options[@]}" --simulate --no-download purge "${packages[@]}" >"$workspace/removal.log" 2>&1 || {
    cat "$workspace/removal.log" >&2
    exit 1
}
while read -r action package remainder; do
    if [[ "$action" == Inst ]] || { [[ "$action" == Remv || "$action" == Purg ]] &&
        [[ ! "$package" =~ ^(thunderbird|rhythmbox|remmina|shotwell)([-:][a-z0-9.+:-]+)?$ && "$package" != ubuntu-desktop ]]; }; then
        cat "$workspace/removal.log" >&2
        printf 'Refusing desktop cleanup that changes an unrelated package: %s %s\n' "$action" "$package" >&2
        exit 1
    fi
done <"$workspace/removal.log"
if [[ "$mode" == --simulate ]]; then
    cat "$workspace/removal.log"
else
    apt-get "${apt_options[@]}" --no-download -y purge "${packages[@]}"
fi