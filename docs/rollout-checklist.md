# Corporate rollout acceptance

[Overview and quick start](../README.md) | [Deployment status](deployment-status.md)

This remains a pilot implementation. Before approving a release, validate all
of the following on clean machines of each intended architecture and hardware:

- Language and keyboard-layout selection appear during installation. A chosen
  non-US layout works in the installer, at disk unlock, at GDM, and on the desktop.
  Verify required language support is available offline; extra language packs
  absent from the source ISO may require internet after installation.
- Installation completes from the newly built ISO without conffile prompts.
- Graphical login appears with networking disconnected and while Defender is
  temporarily unhealthy. Security services remain enabled and recover when
  connectivity is restored.
- A new pilot user signs in through GDM with a full UPN, completes tenant MFA,
  creates a home directory, and reaches the desktop.
- Hello PIN setup and subsequent graphical login work after reboot. Record and
  resolve intermittent `PAM_ABORT` errors; successful PIN login alone does not
  validate the initial password/MFA flow.
- After successful graphical sign-in and reboot, the returning user can select
  their cached account without retyping the UPN and must still authenticate.
  **Not listed?** permits a different user's first sign-in. Approve exposing
  cached account names at the login screen.
- VS Code launches on each architecture. On amd64, Edge and Intune Portal launch
  and authenticate with Microsoft's broker without breaking GDM/PAM sign-in.
  Verify the selected broker and that no unintended duplicate device is enrolled.
- First desktop login does not launch Welcome/Initial Setup. Writer is unpinned,
  the architecture-appropriate browser is pinned, and standard shortcuts remain.
  Users can change favorites without a policy resetting them at the next login.
- An intended Entra user receives authenticated sudo access, can inspect system
  logs, and sees `root` from `sudo whoami`. Confirm that granting every mapped
  `himmelblau-users` member administrator rights matches company policy.
- The provisional hostname is unique and not `localhost`. First Entra login
  personalizes it once; reboot and a different user's login do not change it.
  Confirm corresponding cloud inventory names.
- Thunderbird, Rhythmbox, Remmina, and Shotwell are absent after cleanup,
  including any preseeded Snap copies. The cleanup timer reports errors and
  retries if snapd is not ready; graphical login remains available.
- Every new device appears with its own identity in Entra, Intune, and Defender.
  Intune policy evaluation and Conditional Access produce intended results;
  neither local readiness nor successful sign-in proves enrollment or compliance.
- An administrator can recover the encrypted machine and collect authentication
  logs when Entra sign-in is unavailable. Entra users can use sudo after successful
  authentication, but no local fallback account is created. Manage recovery
  credentials separately.
- Updates, network loss, and hardware or VM suspend/resume are tested. Approve
  the package channel, signature-verification limitations, and support model
  before adopting the image for company use.

The [verification guide](verify-setup.md) provides commands for collecting local
evidence. Review [ARM64 limitations](arm64-support.md) separately.