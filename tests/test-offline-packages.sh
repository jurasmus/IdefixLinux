#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd)"
package_directory="$(realpath -- "${1:?Provide the ARM64 offline package bundle}")"
status_file="${2:-/var/lib/dpkg/status}"
workspace="$(mktemp -d)"
trap 'rm -rf -- "$workspace"' EXIT
mkdir "$workspace/lists" "$workspace/empty"
cp -- "$status_file" "$workspace/status"
cat >"$workspace/apt.conf" <<EOF
Dir::State::status "$workspace/status";
Dir::State::lists "$workspace/lists";
Dir::Etc::sourcelist "/dev/null";
Dir::Etc::sourceparts "$workspace/empty";
EOF
export APT_CONFIG="$workspace/apt.conf"
if apt-get --simulate --no-download --no-remove install "$package_directory/"libmount1_*.deb \
    >"$workspace/old-solver.log" 2>&1; then
    printf 'FAIL: the original forced-version command did not reproduce the conflict.\n' >&2
    exit 1
fi
grep -Eq 'unmet dependencies|Unable to satisfy dependencies' "$workspace/old-solver.log" || {
    cat "$workspace/old-solver.log" >&2
    exit 1
}
bash "$script_directory/install-offline-packages.sh" "$package_directory" --simulate \
    >"$workspace/new-solver.log" 2>&1 || { cat "$workspace/new-solver.log" >&2; exit 1; }
if grep -Eq '^Inst (util-linux|libmount1|libblkid1|libsmartcols1|uuid-runtime) ' "$workspace/new-solver.log"; then
    cat "$workspace/new-solver.log" >&2
    printf 'FAIL: the replacement unexpectedly changes the installed util-linux family.\n' >&2
    exit 1
fi
grep -q '^Inst mdatp ' "$workspace/new-solver.log"
grep -q '^Inst himmelblau ' "$workspace/new-solver.log"
printf 'PASS: forced library upgrade conflict reproduced; local repository installs onboarding packages and retains the installed util-linux family.\n'
bash "$script_directory/cleanup-desktop-apps.sh" --simulate "$status_file" \
    >"$workspace/desktop-removal.log" 2>&1 || { cat "$workspace/desktop-removal.log" >&2; exit 1; }
for application in thunderbird rhythmbox remmina shotwell; do
    grep -Eq "^(Remv|Purg) $application " "$workspace/desktop-removal.log"
done
printf 'PASS: the four selected Debian app families can be removed without unrelated package changes.\n'
cp -- "$status_file" "$workspace/protected-status"
cat >>"$workspace/protected-status" <<'PROTECTED_PACKAGE'

Package: protected-desktop-fixture
Status: install ok installed
Priority: optional
Section: misc
Architecture: all
Version: 1.0
Depends: remmina
Description: Regression fixture protecting an unrelated desktop dependency

PROTECTED_PACKAGE
if bash "$script_directory/cleanup-desktop-apps.sh" --simulate "$workspace/protected-status" \
    >"$workspace/protected-removal.log" 2>&1; then
    printf 'FAIL: cleanup allowed an unrelated package to be removed.\n' >&2
    exit 1
fi
grep -q 'Refusing desktop cleanup.*protected-desktop-fixture' "$workspace/protected-removal.log"
printf 'PASS: cleanup refuses an unrelated reverse-dependency removal.\n'

apparmor_archives=("$package_directory"/himmelblau-apparmor_*.deb)
[[ ${#apparmor_archives[@]} -eq 1 && -f "${apparmor_archives[0]}" ]]
mkdir -p "$workspace/root/etc/apparmor.d/local"
printf 'existing local configuration\n' >"$workspace/root/etc/apparmor.d/local/usr.sbin.cupsd"
dpkg_options=(--root="$workspace/root" --force-not-root --force-script-chrootless --force-depends --force-architecture)
if dpkg "${dpkg_options[@]}" --install "${apparmor_archives[0]}" </dev/null \
    >"$workspace/conffile-before.log" 2>&1; then
    printf 'FAIL: the original install did not reproduce the conffile prompt.\n' >&2
    exit 1
fi
grep -q 'end of file on stdin at conffile prompt' "$workspace/conffile-before.log" || {
    cat "$workspace/conffile-before.log" >&2
    exit 1
}
if ! dpkg "${dpkg_options[@]}" --force-confnew --configure himmelblau-apparmor </dev/null \
    >"$workspace/conffile-after.log" 2>&1; then
    cat "$workspace/conffile-after.log" >&2
    exit 1
fi
dpkg-deb --fsys-tarfile "${apparmor_archives[0]}" | tar -xOf - ./etc/apparmor.d/local/usr.sbin.cupsd \
    >"$workspace/expected-profile"
cmp "$workspace/expected-profile" "$workspace/root/etc/apparmor.d/local/usr.sbin.cupsd"
printf 'PASS: conffile stdin failure reproduced; maintainer policy installs without interactive input.\n'