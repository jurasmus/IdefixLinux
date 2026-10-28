# Install on a machine

[Overview and quick start](../README.md) | [Build the ISO](build-iso.md)

Test on a disposable computer or VM before production use. Keep LUKS recovery
credentials and installation media available: no local fallback account is
created. Review the [rollout checklist](rollout-checklist.md).

## Installation

1. Write the generated offline ISO to a USB drive using your preferred imaging
   tool. Writing the ISO erases the USB drive.
2. Boot the target computer from USB.
3. Select your language and keyboard layout, including its variant. Check the
   keys in the installer's test field before entering an encryption passphrase.
   Choose the target disk carefully and configure encryption according to your
   organization's policy. Networking can remain disconnected during OS
   installation. You will not be asked to create a local account.
4. The installer installs the embedded Defender and pinned Himmelblau packages,
   configures Entra authentication, then reboots. It does not run the upstream
   bootstrap installer or fetch packages. Setup includes AppArmor support and
   required PAM/NSS, SSO, and HSM components, but not the optional browser
   orchestrator.
5. Remove the installation medium when prompted and boot the installed disk.
6. Connect to the internet using the login screen's network controls. New users
   choose **Not listed?**, if shown, and enter their full work UPN, for example
   `alex@contoso.com`. Returning users can select a cached account. Complete the
   authentication and MFA prompts required by your tenant. Approve only the
   sign-in you initiated and enter credentials directly on the device.
7. Complete Hello PIN setup if prompted, then check the desktop and applications.
   Reboot to test remembered-account selection and subsequent PIN login.
8. Verify the device separately in Entra, Intune, and Defender. Installation or
   successful sign-in alone does not establish enrollment or compliance.

## First boot and graphical login

Ubuntu starts graphical login ordered after the Himmelblau services. GDM's
local-user initial-setup wizard is disabled. No automatic login is configured.
Offline installation does not create a cached Entra user; first sign-in needs
tenant connectivity. Himmelblau integrates with the authentication conversation;
no separate enrollment application must open before login.

A readiness timer checks Defender and Himmelblau after boot and retries every
two minutes until initial health is confirmed. Each invocation is bounded;
failures and retries do not block graphical login. From an administrator session:

```bash
sudo journalctl -b -u linux-onboarding-ready.service
systemctl status linux-onboarding-ready.timer
```

## Applications and desktop

VS Code is available on both architectures. On amd64, Edge and Intune Portal
are available too. Do not run the online installer sample inside the offline
installer; these packages and dependencies are already bundled.

Installing Intune Portal does not itself enroll the device. First check the
identity and enrollment established by Himmelblau; do not initiate a second
enrollment blindly. Validate the Portal's sign-in, existing-device handling, and
policy results with a pilot account.

The desktop does not automatically launch Welcome. Writer is unpinned and Edge
is pinned instead of Firefox on amd64; ARM64 keeps Firefox. Files, App Center,
and Help remain pinned. Users can customize favorites normally. See
[deployment profiles](deployment-status.md) for app removal and desktop details.

## VirtualBox pilots

Keep the Windows host awake and connected to power. Screen lock and system
sleep are different settings. Host Modern Standby caused long VM heartbeat gaps
and guest watchdog timeouts during testing; a successful ISO installation does
not validate suspend/resume behavior.

Continue with [sign-in and enrollment behavior](entra-sign-in.md) and
[verification and diagnostics](verify-setup.md).