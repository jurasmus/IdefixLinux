# Before you start

[Overview and quick start](../README.md)

Prepare the following:

- An unmodified Ubuntu 26.04 Desktop amd64 or arm64 ISO. Ubuntu Server, other
  desktop flavors, and other Ubuntu releases are not supported by this builder.
- A Defender for Endpoint Linux onboarding package downloaded from the Microsoft
  Defender portal. Extract it and identify its JSON onboarding file.
- Your Entra sign-in domain, for example `contoso.com`.
- An Ubuntu machine or Ubuntu WSL environment with `xorriso`, `squashfs-tools`,
  `jq`, `curl`, `apt`, `dpkg`, `ubuntu-keyring`, and standard GNU utilities.
  No Docker or root access is needed to build. Installing build dependencies
  requires sudo. Allow space for the output ISO, temporary ISO, and several
  hundred MB of packages.
- Internet access on the build machine to download packages. Installation uses
  embedded packages; first Entra sign-in, Intune enrollment, Defender cloud
  connectivity, and subsequent updates still require internet access.
- Tenant licensing and policies that allow the intended user to register a
  device and enroll it in Intune. Check Intune and Defender licensing as required
  by your organization.

## Himmelblau package channel

The scripts use a pinned free Community Nightly snapshot, currently
`2026-10-24-2ad5a39cf571`, package version `5.0.0-ubuntu26.04~20261024`.
It does not require a stable-repository entitlement token. Nightly packages are
development builds, not a maintained production release. Use this channel only
if you accept development-build stability and support tradeoffs. Read the
[package authenticity limitations](package-bundles.md) before building.

## Access and recovery

No group allow-list is configured. Any Entra user can attempt to sign in, subject
to tenant authentication and device-registration policies. A successfully mapped
user in `himmelblau-users` receives authenticated sudo access. Approve this
[administrator model](local-administration.md) before rollout.

The ISO creates no local fallback account. Keep LUKS recovery credentials and
installation media available, and test recovery before broad deployment.

The generated ISO contains tenant-specific Defender onboarding JSON. Keep the
JSON and ISO outside source control, and do not publish them.

Next: [build the ISO](build-iso.md). For ARM64, also review
[hardware and support limitations](arm64-support.md).