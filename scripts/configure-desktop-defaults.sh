#!/usr/bin/env bash
set -euo pipefail

configure_desktop_defaults() {
    local root_directory="$1" architecture="$2" browser favorites schema_directory
    case "$architecture" in
        amd64)
            browser=microsoft-edge.desktop
            [[ -f "$root_directory/usr/share/applications/$browser" ]] || {
                printf 'Microsoft Edge launcher is missing.\n' >&2
                return 1
            }
            ;;
        arm64) browser=firefox_firefox.desktop ;;
        *) printf 'Unsupported desktop architecture: %s\n' "$architecture" >&2; return 1 ;;
    esac
    schema_directory="$root_directory/usr/share/glib-2.0/schemas"
    [[ -d "$schema_directory" ]] || return 1
    install -d -m 0755 "$root_directory/etc/systemd/user" "$root_directory/etc/xdg/autostart"
    ln -sfn /dev/null "$root_directory/etc/systemd/user/gnome-initial-setup-first-login.service"
    ln -sfn /dev/null "$root_directory/etc/systemd/user/gnome-initial-setup-upgrade-login.service"
    cat >"$root_directory/etc/xdg/autostart/gnome-initial-setup-first-login.desktop" <<'AUTOSTART'
[Desktop Entry]
Type=Application
Name=Welcome to Ubuntu
Hidden=true
AUTOSTART
    favorites="['$browser', 'org.gnome.Nautilus.desktop', 'snap-store_snap-store.desktop', 'org.gnome.Yelp.desktop']"
    cat >"$schema_directory/99_linux-onboarding.gschema.override" <<EOF
[org.gnome.shell]
favorite-apps=$favorites

[org.gnome.shell:ubuntu]
favorite-apps=$favorites
EOF
    chmod 0644 "$root_directory/etc/xdg/autostart/gnome-initial-setup-first-login.desktop" \
        "$schema_directory/99_linux-onboarding.gschema.override"
    glib-compile-schemas --strict "$schema_directory"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    [[ $EUID -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }
    configure_desktop_defaults / "$(dpkg --print-architecture)"
fi