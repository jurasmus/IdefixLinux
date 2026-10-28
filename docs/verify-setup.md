# Verify setup and troubleshoot

[Overview and quick start](../README.md) | [Rollout checklist](rollout-checklist.md)

## Services and applications

On the installed machine:

```bash
mdatp health --field org_id
mdatp health --field healthy
mdatp health --field real_time_protection_enabled
systemctl status mdatp himmelblaud himmelblaud-tasks
systemctl status display-manager linux-onboarding-ready.timer
systemctl get-default
systemctl status linux-desktop-cleanup.timer
code --version
hostnamectl --static
sudo -l
```

The default target must be `graphical.target`. On amd64, also check
`microsoft-edge --version` and launch Intune Portal from the application menu.

## Desktop cleanup

From an administrator session:

```bash
sudo journalctl -b -u linux-desktop-cleanup.service
snap list
dpkg-query -W thunderbird rhythmbox remmina shotwell
```

After removal, these Debian packages should not be installed; `dpkg-query` may
report no matching packages. Cleanup records initial completion at
`/var/lib/linux-onboarding/desktop-apps-removed`.

## Graphical login and readiness

If graphical login fails, collect these logs from an administrator session or
use recovery media if no session is available. Standard Entra users may not
have permission to read them:

```bash
sudo journalctl -b -u gdm.service -u himmelblaud.service -u himmelblaud-tasks.service
sudo journalctl -b -u linux-onboarding-ready.service
```

Readiness failures are reported and retried independently of graphical login.
Keep the security services and Himmelblau sandbox enabled when investigating.

## Local compliance diagnostics

New installations include a read-only diagnostic command:

```bash
sudo managed-compliance
```

It prints PASS/FAIL for the eight discovery checks and Defender/Himmelblau
services, followed by Secure Boot, disk layout, Defender health, service status,
and enrollment config visibility. Diagnostic commands have time limits. Exit
codes are 0 for passing checks, 1 for failed checks, and 2 for usage or
permissions. Output can contain device and organization identifiers; review it
before sharing. The command does not change settings or query Intune.

For an existing machine, transfer the updated
[compliance/compliance.sh](../compliance/compliance.sh), then run from the
directory containing that transferred file; no reinstall or full onboarding
rerun is needed:

```bash
sudo install -o root -g root -m 0755 compliance.sh /usr/local/bin/managed-compliance
sudo managed-compliance
```

The original discovery script supports `--debug`. Without arguments it returns
only Intune JSON:

```bash
sudo /opt/linux-onboarding/compliance.sh | jq .
```

For root-only diagnostic output:

```bash
sudo /opt/linux-onboarding/compliance.sh --debug
```

## Interpreting encryption and enrollment

Encryption detection checks for any `crypt` device, with a fallback to active
LUKS1/LUKS2 device-mapper UUIDs in sysfs when a private `/dev` namespace hides
devices from `lsblk`. It does not prove that every data volume is encrypted.
Debug output includes the root filesystem, disk layout, and device-mapper UUIDs
to investigate discrepancies. No extra device access or passwordless sudo is
needed; keep Himmelblau's service sandbox enabled.

`IntuneEnrollmentCompleted` becomes true after Himmelblau records an
`intune_device_id`. Local status is not a substitute for confirming the device
and policy status in Microsoft portals. Root diagnostics also do not prove
that discovery has the same access when run by a compliance agent. See
[Intune custom compliance](custom-compliance.md).