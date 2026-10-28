# Build an Ubuntu ISO with Entra sign-in, Intune and Defender

A fresh Linux workstation should not need a second setup session just to add
the organization's authentication and security tools. This project puts that
configuration into the installation media: build a private Ubuntu Desktop ISO,
install the machine, then sign in with a work account.

The image embeds Microsoft Defender for Endpoint, Himmelblau for Entra sign-in,
and the packages they need. OS installation can run offline. First Entra
authentication, Intune enrollment, Defender cloud connectivity, and updates
still need internet access.

The workflow is **prepare the tenant, build the ISO, install Ubuntu, sign in,
and verify**. There is no separate onboarding command to run on the new machine
after installation.

## Start with a pilot, not a production promise

This is a pilot implementation for Ubuntu 26.04 Desktop, with separate amd64 and
ARM64 images. It uses pinned Himmelblau Community Nightly packages without
upstream APT signatures and an experimental Hello MFA flow. Local package hashes
detect corruption, but are not independent proof of publisher authenticity.

The ISO creates no local fallback account. Every mapped member of the local
`himmelblau-users` group receives authenticated sudo access. Before testing,
approve that administrator model and arrange disk recovery credentials and
recovery media. This is not a zero-touch deployment: language, keyboard, network,
disk, and encryption choices remain interactive.

ARM64 also has a different support boundary. Himmelblau's enrollment implementation
does not establish Microsoft-supported ARM64 Intune enrollment. The ARM64 image
includes VS Code and Firefox, but not official Edge or Intune Portal packages.
Read the [deployment status](deployment-status.md) and
[ARM64 limitations](arm64-support.md) before selecting hardware.

## Prepare the tenant before building the image

The ISO cannot create licenses, tenant policies, compliance assignments, or a
Defender onboarding package. Prepare those first:

1. Confirm the pilot user's Intune and Defender licensing and the tenant policies
   needed for the intended Entra registration and enrollment flow.
2. Download a Linux onboarding package from the Defender portal and extract its
   JSON file. Keep it outside source control.
3. Add [compliance/compliance.sh](../compliance/compliance.sh) to Intune as a Linux
   custom compliance discovery script.
4. Create a Linux compliance policy, enable **Custom Compliance**, select that
   script, and upload [compliance/rules.json](../compliance/rules.json).
5. Assign the policy to a small pilot group and plan to verify its results after
   the machine enrolls.

The discovery script reports local state; the rules define what Intune requires.
Both need to be configured in Intune. Embedding the discovery script in the ISO
does not create or assign the tenant's compliance policy.

Do not assume discovery runs as root. Microsoft's Linux discovery workflow uses
the signed-in user's context; Himmelblau's execution path can differ. Validate
the actual context and permissions used by your enrollment implementation. The
[custom compliance guide](custom-compliance.md) covers this distinction.

## Build the installation ISO

Use an Ubuntu machine or Ubuntu WSL environment and an unmodified Ubuntu 26.04
Desktop ISO for the target architecture. The build downloads packages, so the
build machine needs internet access. Docker is not required.

From the repository root, install the build dependencies:

```bash
sudo apt-get update
sudo apt-get install -y xorriso squashfs-tools jq curl apt dpkg ubuntu-keyring ca-certificates
```

Then build the image, replacing the paths and domain with your own. The private
output directory must already exist:

```bash
bash scripts/build-onboarding-iso.sh \
  --iso /path/to/ubuntu-26.04.1-desktop-amd64.iso \
  --output /path/to/private/ubuntu-26.04-offline-amd64.iso \
  --mde-onboarding-file /path/to/private/mdatp_onboard.json \
  --himmelblau-domain contoso.com
```

For ARM64, use an ARM64 source ISO and a separate output filename. The builder
detects architecture from the media; no architecture flag is needed. The build
itself does not require sudo or execute target binaries.

The builder downloads the package bundle, checks dependencies against the source
image, embeds the installation helpers, updates checksums, and preserves the
source ISO's boot settings. It refuses to overwrite an existing output file and
prints a SHA-256 hash to keep with deployment records.

The resulting ISO contains the organization's Defender onboarding JSON. Keep it
private: publish the project source, not a tenant-specific image or onboarding
file. For repeated builds, a [reusable package bundle](package-bundles.md) avoids
downloading the same packages again. The [build guide](build-iso.md) includes
complete amd64, ARM64, and WSL examples.

## Install a clean machine

Use a disposable pilot machine or VM first. Back up target-disk data before
installation and keep recovery credentials separately.

1. Write the generated ISO to USB and boot from it. Imaging erases the USB drive.
2. Select the language and keyboard layout, including its variant. Test the keys
   before entering an encryption passphrase.
3. Choose the correct target disk and configure encryption according to company
   policy. Configure Secure Boot in compatible firmware as required; creating
   the ISO does not enable it for you.
4. Complete installation. Networking can remain disconnected during this phase.
   The installer does not ask you to create a local account.
5. Remove the installation medium when prompted and boot the installed disk.

During installation, the embedded helpers install and configure Defender and
Himmelblau, set up authentication, assign a unique provisional hostname, and
apply the desktop profile. You do not copy scripts onto the installed machine
or run a second bootstrap command.

VS Code is included on both architectures. On amd64, Edge and Intune Portal are
included with Microsoft's identity broker; ARM64 keeps Himmelblau's broker.
Thunderbird, Rhythmbox, Remmina, and Shotwell are selected for removal. A separate
first-boot timer handles any Snap copies without blocking graphical login.

## Sign in with a work account

At graphical login, connect to the internet. Choose **Not listed?**, if shown,
and enter the full work UPN, such as `alex@contoso.com`. Complete the tenant's
authentication and MFA prompts directly on the device. An offline OS install
has not created a cached Entra user, so first sign-in needs tenant connectivity.

After initial successful authentication, Himmelblau can offer Hello PIN setup.
Test a reboot and subsequent PIN login rather than assuming the first desktop
session proves the complete authentication flow. Returning users can select a
cached account without retyping the UPN; authentication is still required.
Conditional Access and tenant policies can require additional authentication.

The desktop suppresses automatic Welcome startup and uses customizable dock
defaults. A first-login hook can personalize the hostname once. Graphical login
is not held behind Defender health checks: a separate readiness timer reports
and retries failures while security services remain enabled.

Intune Portal being installed does not itself enroll the machine. Check the
identity established by Himmelblau before initiating any additional enrollment;
do not create a duplicate blindly. Every new machine must create its own device
identity, so do not clone a disk after Entra or Intune registration.

For the detailed flow, see [installation](install-linux.md),
[sign-in and enrollment](entra-sign-in.md), and
[local administration and naming](local-administration.md).

## Verify the device locally and in the portals

After sign-in, inspect Defender and the authentication services:

```bash
mdatp health --field org_id
mdatp health --field healthy
mdatp health --field real_time_protection_enabled
systemctl status mdatp himmelblaud himmelblaud-tasks
```

The image also installs a read-only local diagnostic command:

```bash
sudo managed-compliance
```

It checks Secure Boot, detected LUKS encryption, Defender installation and
onboarding, Defender health and real-time protection, Himmelblau installation,
and locally recorded Intune enrollment. Encryption detection does not prove all
data volumes are encrypted. Enrollment discovery becomes true when Himmelblau
records an `intune_device_id`; that record alone does not prove cloud compliance.

Review diagnostic output before sharing it because it can contain device and
organization identifiers. Root-only local diagnostics do not prove that the
compliance agent has the same access to every setting.

Finally, confirm the device's own identity in Entra, enrollment and custom policy
evaluation in Intune, and onboarding in Defender. A completed installation,
successful login, or passing local check is not a substitute for those results.

## A repeatable fresh-install workflow

Once the tenant and image are prepared, the next pilot machine follows the same
path: boot the private ISO, choose installation settings, install, sign in, and
verify. The device-side setup is part of installation rather than a collection
of post-install commands.

Before wider deployment, complete the [rollout checklist](rollout-checklist.md),
including first-login MFA, PIN login, keyboard behavior at disk unlock and GDM,
recovery, cloud policy results, updates, and suspend/resume. For VM pilots, keep
the host awake and connected to power. Package maintenance, the unsigned Nightly
channel, recovery access, and the administrator model remain explicit deployment
decisions, not problems that a successful ISO build resolves.