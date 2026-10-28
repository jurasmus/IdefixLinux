# Package sources and reusable bundles

[Overview and quick start](../README.md) | [Build the ISO](build-iso.md)

## Sources and signature verification

The published Himmelblau Nightly APT directories currently have an empty
`Packages` index and no signed `Release` metadata. This causes the bootstrap
installer's 404. The builder instead downloads selected Himmelblau `.deb` files
from a specific official HTTPS snapshot.

These downloads do **not** have upstream APT signature verification. Package
names, versions, and architectures are checked, and local SHA-256 hashes detect
corruption after download; those hashes are not independent proof of publisher
authenticity.

Ubuntu, Defender, Edge, VS Code, Intune Portal, and their dependencies use signed
APT repositories. Edge and VS Code use the legacy `microsoft.asc` signing key;
the Ubuntu 26.04 Microsoft repository uses `microsoft-2025.asc`. These keys are
kept separate, following
[Microsoft's Intune installer sample](https://github.com/microsoft/shell-intune-samples/tree/master/Linux/Intune%20Installer).
No insecure remote APT override is enabled.

## Architecture-specific brokers

On amd64, Intune Portal requires Microsoft's identity broker, which conflicts
with the pinned `himmelblau-broker` package. The image selects only Microsoft's
broker on amd64. The Himmelblau SSO package explicitly accepts either broker;
PAM, NSS, and Himmelblau sign-in remain installed.

ARM64 selects Himmelblau's broker and omits the unavailable official Edge/Intune
applications. Validate SSO and enrollment with the selected broker in your
tenant; the two implementations are not installed together.

## Prepare and reuse a bundle

To keep exactly the same packages for subsequent builds, prepare a bundle once
from the repository root:

```bash
bash scripts/prepare-onboarding-packages.sh \
  --architecture arm64 \
  --output /mnt/c/GitHub/tmp/onboarding-packages-arm64-v5
```

Add `--package-directory /mnt/c/GitHub/tmp/onboarding-packages-arm64-v5` to the
[ISO build command](build-iso.md) to reuse it without package downloads. Use
`amd64` and a separate bundle directory for an amd64 ISO. Output bundle
directories must not already exist.

Older bundles without the required apps and signing key are rejected. Prepare a
new bundle instead of modifying an existing bundle's signed-package contents.
To deliberately select a newer Himmelblau snapshot, pass both
`--himmelblau-build DATE-COMMIT` and `--himmelblau-version VERSION` to preparation.
It does not silently fall back to another Ubuntu release or build.

## Offline installation behavior

The ISO includes package versions and hashes under `/onboarding/packages/`.
Installation verifies hashes and creates a temporary local `file:` APT
repository with remote sources disabled. Only onboarding packages listed in
`package-names` are requested; dependencies are available locally when needed.
Compatible installed base packages are retained instead of forcing every
bundled `.deb` version onto the target.

For fresh installs, dpkg uses `--force-confnew` to select bundled maintainer
configuration files when they conflict with existing files, including
Ubuntu-created AppArmor local snippets. This avoids installer conffile prompts
and ensures Himmelblau's rules are installed. Do not use this helper to preserve
customized configuration on an existing deployment.

APT can copy files from the local repository but has no remote package source.
Subiquity has no remote mirror candidates, uses offline fallback, and does not
refresh the installer or download drivers/OEM packages. Maintenance scripts may
attempt nonessential network calls such as Defender telemetry; this is an
offline-capable installation, not a guarantee of zero traffic.

After installation, `/opt/linux-onboarding/package-versions.tsv` records bundle
versions. Temporary package copies are removed from the target.

## Updates

Microsoft repositories and signing keys are retained for online Defender, VS
Code, and architecture-appropriate Edge/Intune updates. No broken Himmelblau
Nightly repository is added. Plan and pilot Himmelblau upgrades explicitly using
a new verified bundle or working upstream repository; retaining the pinned
development snapshot indefinitely is not an update strategy.