# Deployment status

[Overview and quick start](../README.md)

This image is a pilot implementation, not a production-qualified corporate image.
It uses pinned Himmelblau Nightly packages without upstream APT signatures and an
experimental Hello MFA flow. ARM64 Himmelblau enrollment is not the same as
Microsoft's supported x86/64 Intune enrollment workflow. Graphical login, first
Entra authentication, PIN setup, and tenant enrollment must be validated together
on each intended hardware and architecture before company rollout.

## Boot and security services (v4)

Ubuntu's graphical login starts independently of Defender health. An initially
unhealthy security service is reported and retried in the background; it does not
leave a new machine without a login screen. Defender, AppArmor, and PAM
authentication remain enabled. This does not declare the machine compliant or
bypass tenant Conditional Access requirements.

## Application profile (v5)

The image includes architecture-appropriate Microsoft apps and removes
Thunderbird, Rhythmbox, Remmina, and Shotwell from the installed system. Debian
packages, including their app-specific plugins and locale packages, are purged
during installation. A separate first-boot timer removes any Snap copies,
including Thunderbird. It retries snapd errors without blocking graphical login;
an app icon can remain visible briefly until cleanup finishes.

Shared libraries and unrelated desktop applications are not automatically
removed. The original live-media squashfs layers are retained, so this is not an
ISO-size reduction.

## Local administration and naming (v6)

Members of the local `himmelblau-users` group receive full local administrator
access through sudo, with authentication required. The installer assigns a unique
hostname before first boot and personalizes it once after the first successful
Entra login. All mapped Entra users in this group are administrators; this is not
an administrator-only Entra group policy. Approve this privilege model before
rollout. See [local administration and device names](local-administration.md).

## Desktop defaults (v7)

Automatic GNOME Welcome/Initial Setup launches are suppressed at first login and
after upgrades. The initial dock contains the browser, Files, App Center, and
Help, with LibreOffice Writer unpinned. Edge replaces the Firefox pin on amd64;
ARM64 keeps Firefox because no official Edge package is available.

Writer and Firefox are not uninstalled, and default-browser associations are not
changed. These are customizable defaults, not locked preferences; existing users
who have already customized their dock keep their own pins.

## Remembered accounts (v8)

GDM's remembered-user list is enabled. After a successful graphical sign-in, a
cached account can be selected on subsequent boots instead of typing its UPN
again. New users choose **Not listed?** and enter their full UPN. This exposes
cached account names at the login screen; it does not enable automatic login or
remove PIN/password and tenant MFA requirements. See the
[existing-machine instructions](remembered-users.md).

## Installer language and keyboard (v9)

The installer shows language and keyboard-layout selection before network and
storage setup. Choose the intended keyboard layout and variant before entering
an encryption passphrase or authenticating. This does not re-enable the desktop
Welcome wizard or create a local account.

Complete the [rollout checklist](rollout-checklist.md) before approving a release.