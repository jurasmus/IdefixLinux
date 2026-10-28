# ARM64 validation and support

[Overview and quick start](../README.md)

Use an ISO compatible with the target computer's firmware and hardware; a
generic ARM64 ISO does not support every ARM device. Boot and installation,
Defender health, Himmelblau sign-in, Hello PIN setup, and Intune enrollment must
be validated on a pilot machine before rollout.

Microsoft lists Ubuntu 26.04 ARM64 in the
[Defender support matrix](https://learn.microsoft.com/en-us/defender-endpoint/mde-linux-prerequisites).
Linux desktop Defender support is currently Public Preview. Himmelblau's
[package server](https://packages.himmelblau-idm.org/nightly/) publishes ARM64
Ubuntu Nightly packages, but availability and repository metadata can change.

Microsoft's
[official Intune Linux enrollment workflow](https://learn.microsoft.com/en-us/intune/intune-service/user-help/enroll-device-linux)
specifies x86/64 CPUs. Himmelblau uses a separate enrollment implementation;
ARM64 package support does not establish Microsoft-supported Intune enrollment
or compliance.

Official Edge and Intune Portal packages are absent from Microsoft's ARM64
repository indexes. An architecture listed in repository Release metadata alone
does not establish that an application is published for it. The ARM64 image
includes VS Code, keeps Firefox, and selects Himmelblau's broker. No x86
emulation or unofficial replacement is used.

Confirm enrollment and policy results in your tenant. See
[package and broker selection](package-bundles.md) and the
[rollout checklist](rollout-checklist.md).