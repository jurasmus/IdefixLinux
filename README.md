# Ubuntu 26.04 Entra, Intune, and Defender installation

Build an Ubuntu 26.04 Desktop installation ISO with Microsoft Entra sign-in
through Himmelblau, Microsoft Defender for Endpoint, and offline application
packages. Supports separate amd64 and ARM64 images.

OS installation can run offline. First Entra sign-in, device enrollment, cloud
security services, and updates require internet access. Language, keyboard,
network, disk, and encryption choices remain interactive.

## Important before you begin

- **Pilot only:** pinned Himmelblau Nightly packages lack upstream APT signatures,
  and Hello MFA is experimental. Read the [deployment status](docs/deployment-status.md)
  and [package limitations](docs/package-bundles.md) before use.
- **No local fallback account:** keep disk recovery credentials and installation
  media available. Every mapped `himmelblau-users` member receives authenticated
  sudo access; approve this [administrator model](docs/local-administration.md).
- **Keep the ISO private:** it contains tenant-specific Defender onboarding JSON.
  Do not commit or publish the JSON or generated image.
- **ARM64 has different support limits:** Himmelblau enrollment does not establish
  Microsoft-supported ARM64 Intune enrollment. See [ARM64 support](docs/arm64-support.md).

## Solution components

| Component | Role |
| --- | --- |
| ISO builder and offline bundle | Embed packages and configure Ubuntu installation without remote APT sources. |
| Himmelblau | Entra authentication, experimental Hello PIN, and tenant-dependent device registration/enrollment. |
| Defender for Endpoint | Tenant onboarding and endpoint protection. |
| Desktop helpers | App cleanup, dock defaults, authenticated sudo, unique naming, and nonblocking readiness checks. |
| Custom compliance | Local discovery script and matching Intune rules; portal validation is still required. |

| Included apps | amd64 | ARM64 |
| --- | --- | --- |
| Visual Studio Code | Yes | Yes |
| Microsoft Edge and Intune Portal | Yes, with Microsoft's broker | Unavailable; Firefox and Himmelblau's broker retained |

See the [component and script reference](docs/components.md) for individual files,
repository layout, and test commands.

## Create an ISO

1. Get an **unmodified Ubuntu 26.04 Desktop ISO** for the target architecture,
   your Defender onboarding JSON, and your Entra domain. Keep private files
   outside the repository. Confirm [build and tenant prerequisites](docs/prerequisites.md).
2. Open Ubuntu or WSL, change to the repository root, and install dependencies:

   ```bash
   sudo apt-get update
   sudo apt-get install -y xorriso squashfs-tools jq curl apt dpkg ubuntu-keyring ca-certificates
   ```

3. Build the image. Replace all example paths and the domain; the private output
   directory must already exist:

   ```bash
   bash scripts/build-onboarding-iso.sh \
     --iso /path/to/ubuntu-26.04.1-desktop-amd64.iso \
     --output /path/to/private/ubuntu-26.04-offline-amd64.iso \
     --mde-onboarding-file /path/to/private/mdatp_onboard.json \
     --himmelblau-domain contoso.com
   ```

4. Keep the printed SHA-256 hash with the private ISO. Existing output files are
   not overwritten. For ARM64, use an ARM64 source ISO and separate output name;
   architecture is detected automatically.

See [detailed build instructions](docs/build-iso.md) for WSL paths and both
architectures, or [reusable package bundles](docs/package-bundles.md) to avoid
repeating downloads.

## Install your Linux machine

1. Write the generated ISO to USB, which erases the USB drive, and boot a pilot
   machine. Back up any target-disk data you need to keep.
2. Select language and keyboard layout, test the keys, choose the target disk,
   and configure encryption. No local account is created. OS installation may
   remain offline.
3. Remove the installation medium when prompted and boot the installed disk.
   Connect to the internet from the graphical login screen.
4. Choose **Not listed?**, if shown, and enter the full work UPN, such as
   `alex@contoso.com`. Complete tenant authentication/MFA and Hello PIN setup if
   prompted. Returning users can select a cached account; this is not automatic login.
5. Reboot and check account selection, PIN login, keyboard layout, and the
   desktop applications. Run `sudo managed-compliance` for local diagnostics.
6. Confirm the device and policy results in Entra, Intune, and Defender. A
   successful installation or login alone does not prove enrollment or compliance.

Follow the [installation guide](docs/install-linux.md) and
[rollout checklist](docs/rollout-checklist.md) for the full acceptance flow.

## Documentation

| Guide | Covers |
| --- | --- |
| [Deployment status](docs/deployment-status.md) | Pilot status and image profiles, v4 through v9. |
| [Before you start](docs/prerequisites.md) | Build tools, private inputs, tenant requirements, and recovery. |
| [Build the ISO](docs/build-iso.md) | Complete amd64/ARM64 build instructions and validation. |
| [Package sources and bundles](docs/package-bundles.md) | Signatures, broker selection, offline behavior, reuse, and updates. |
| [ARM64 support](docs/arm64-support.md) | Hardware, package availability, and support boundaries. |
| [Install on a machine](docs/install-linux.md) | Installation, first boot, applications, and VM precautions. |
| [Entra sign-in and enrollment](docs/entra-sign-in.md) | MFA, Hello PIN, enrollment, and unique device identities. |
| [Local administration and naming](docs/local-administration.md) | Sudo policy and hostname lifecycle. |
| [Remembered users](docs/remembered-users.md) | Enable account selection on an existing machine and roll it back. |
| [Rollout checklist](docs/rollout-checklist.md) | Clean-machine acceptance checks before deployment. |
| [Verification and troubleshooting](docs/verify-setup.md) | Health commands, logs, recovery diagnostics, and interpreting compliance. |
| [Components and tests](docs/components.md) | File reference, repository layout, and regression commands. |
| [Intune custom compliance](docs/custom-compliance.md) | Discovery script and rule-policy configuration. |
| [Existing installations](docs/existing-install.md) | Alternative onboarding without building an ISO. |
| [Device retirement](docs/retire-device.md) | Offboarding and authentication-stack precautions. |

The [walkthrough article](docs/blog.md) follows the ISO build and fresh-install
workflow from tenant preparation to verification.