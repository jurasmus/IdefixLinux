#!/usr/bin/env bash
set -euo pipefail
umask 077

package_directory="$(realpath -- "${1:?Provide the offline package directory}")"
mode="${2:-}"
[[ -z "$mode" || "$mode" == --simulate ]] || { printf 'Unknown mode: %s\n' "$mode" >&2; exit 1; }
[[ -f "$package_directory/SHA256SUMS" && -f "$package_directory/package-names" ]] || {
    printf 'Missing offline package manifest.\n' >&2; exit 1;
}
(cd -- "$package_directory" && sha256sum --check SHA256SUMS >/dev/null)
package_architecture="$(cat "$package_directory/architecture")"
[[ "$package_architecture" == amd64 || "$package_architecture" == arm64 ]] || {
    printf 'Unsupported offline package architecture.\n' >&2; exit 1;
}
[[ "$mode" == --simulate || "$package_architecture" == "$(dpkg --print-architecture)" ]] || {
    printf 'Offline package architecture does not match the system.\n' >&2; exit 1;
}
mapfile -t packages <"$package_directory/package-names"
[[ ${#packages[@]} -gt 0 ]] || { printf 'Empty package selection.\n' >&2; exit 1; }
for package in "${packages[@]}"; do
    [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || { printf 'Invalid package name: %s\n' "$package" >&2; exit 1; }
done
workspace="$(mktemp -d)"
trap 'rm -rf -- "$workspace"' EXIT
mkdir -p "$workspace/repository" "$workspace/lists/partial" "$workspace/cache/archives/partial" "$workspace/empty"
shopt -s nullglob
archives=("$package_directory/"*.deb)
[[ ${#archives[@]} -gt 0 ]] || { printf 'No offline packages found.\n' >&2; exit 1; }
for archive in "${archives[@]}"; do
    filename="$(basename -- "$archive")"
    ln -s -- "$archive" "$workspace/repository/$filename"
    dpkg-deb --field "$archive" | sed '/^$/d'
    printf 'Filename: ./%s\nSize: %s\nSHA256: %s\n\n' \
        "$filename" "$(stat -c %s -- "$archive")" "$(sha256sum -- "$archive" | cut -d ' ' -f 1)"
done >"$workspace/repository/Packages"
printf 'deb [trusted=yes] file:%s ./\n' "$workspace/repository" >"$workspace/offline.list"
apt_options=(-o "Dir::Etc::sourcelist=$workspace/offline.list"
    -o "Dir::Etc::sourceparts=$workspace/empty" -o "Dir::State::lists=$workspace/lists"
    -o "Dir::Cache=$workspace/cache" -o "APT::Sandbox::User=$(id -un)"
    -o "APT::Architecture=$package_architecture" -o APT::Get::List-Cleanup=false -o Acquire::Languages=none)
apt-get "${apt_options[@]}" update
install_options=(--no-remove --no-install-recommends -y -o Dpkg::Options::=--force-confnew)
if [[ "$mode" == --simulate ]]; then
    install_options+=(--simulate)
fi
apt-get "${apt_options[@]}" "${install_options[@]}" install "${packages[@]}"