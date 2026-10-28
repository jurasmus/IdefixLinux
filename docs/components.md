# Repository layout and components

[Overview and quick start](../README.md)

```text
README.md
scripts/       ISO builder, package preparation, and installation helpers
tests/         Manually run regression checks
compliance/    Intune discovery script and matching rules
docs/          Detailed guides and explanatory article
```

Run repository examples from the root. Keep `scripts/` and `compliance/`
together when copying the project. The builder collects files into a flat ISO
payload automatically; installed paths under `/opt/linux-onboarding/` are
unchanged.

## Build and installation helpers

| File | Purpose |
| --- | --- |
| [scripts/build-onboarding-iso.sh](../scripts/build-onboarding-iso.sh) | Remasters Ubuntu with autoinstall, offline packages, and tenant payload. |
| [scripts/prepare-onboarding-packages.sh](../scripts/prepare-onboarding-packages.sh) | Downloads the pinned Himmelblau snapshot and signed Ubuntu/Microsoft apps and dependencies. |
| [scripts/install-offline-packages.sh](../scripts/install-offline-packages.sh) | Uses a temporary local repository while retaining compatible installed base packages. |
| [scripts/onboard-linux.sh](../scripts/onboard-linux.sh) | Configures Defender, Himmelblau, PAM/NSS, Entra domain, authenticated sudo, and naming hook. |
| [scripts/configure-device-name.sh](../scripts/configure-device-name.sh) | Assigns a unique provisional name and personalizes it once after successful Entra login. |
| [scripts/configure-desktop-defaults.sh](../scripts/configure-desktop-defaults.sh) | Suppresses automatic Welcome startup and compiles customizable dock defaults. |
| [scripts/verify-first-boot.sh](../scripts/verify-first-boot.sh) | Performs bounded Defender/Himmelblau health checks; a timer retries independently of login. |
| [scripts/cleanup-desktop-apps.sh](../scripts/cleanup-desktop-apps.sh) | Safely purges the four selected Debian app families and removes Snap copies via a first-boot timer. |

## Compliance and article

| File | Purpose |
| --- | --- |
| [compliance/compliance.sh](../compliance/compliance.sh) | Reports eight local health/enrollment values for Intune discovery and provides local diagnostics. |
| [compliance/rules.json](../compliance/rules.json) | Defines custom compliance rules matching discovery output. |
| [docs/blog.md](blog.md) | Separate explanatory article, not an installer dependency. Use these guides for current procedures. |

## Regression checks

The [graphical-boot suite](../tests/test-graphical-boot.sh) checks generated
systemd units, isolated readiness failure/recovery, installer choices, repository
and ISO payload paths, sudo policy, naming, app cleanup, and desktop defaults.
Run in Ubuntu/WSL with `systemd`, `jq`, `python3-yaml`, and unprivileged user/mount
namespaces available:

```bash
bash tests/test-graphical-boot.sh
```

The [offline-package suite](../tests/test-offline-packages.sh) checks dependency
conflicts, safe desktop-app removal, and noninteractive AppArmor configuration.
It requires an ARM64 offline bundle and the corresponding source ISO's dpkg
status file:

```bash
bash tests/test-offline-packages.sh BUNDLE SOURCE_DPKG_STATUS
```

These are regression checks, not substitutes for clean-machine installation,
graphical authentication, or enrollment testing. Use the
[rollout checklist](rollout-checklist.md) for acceptance.