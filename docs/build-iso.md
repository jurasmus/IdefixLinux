# Build the ISO

[Overview and quick start](../README.md)

Review the [prerequisites](prerequisites.md) first. Run commands from the
repository root, keeping the `scripts/` and `compliance/` directories together.

## Prepare the build machine

1. Open Ubuntu or WSL and change to your copy of the repository:

   ```bash
   cd /path/to/linux-onboarding
   ```

2. Install the dependencies:

   ```bash
   sudo apt-get update
   sudo apt-get install -y xorriso squashfs-tools jq curl apt dpkg ubuntu-keyring ca-certificates
   ```

3. Download the Ubuntu 26.04 Desktop ISO and the Defender for Endpoint Linux
   onboarding package. Extract the package and keep its JSON outside source
   control. For WSL, a Windows folder such as `C:\GitHub\tmp` is available as
   `/mnt/c/GitHub/tmp`:

   ```bash
   ls -lh /mnt/c/GitHub/tmp
   ```

Ubuntu may include a point release in the ISO filename, such as
`ubuntu-26.04.1-desktop-amd64.iso`. Use the filenames you actually downloaded.
The private output directory must already exist.

## Build an amd64 image

Replace the example paths and domain with your own:

```bash
bash scripts/build-onboarding-iso.sh \
  --iso /mnt/c/GitHub/tmp/ubuntu-26.04.1-desktop-amd64.iso \
  --output /mnt/c/GitHub/tmp/ubuntu-26.04-offline-amd64-v9.iso \
  --mde-onboarding-file /mnt/c/GitHub/tmp/mdatp_onboard.json \
  --himmelblau-domain contoso.com
```

## Build an ARM64 image

Use the ARM64 source ISO and a separate output filename:

```bash
bash scripts/build-onboarding-iso.sh \
  --iso /mnt/c/GitHub/tmp/ubuntu-26.04-desktop-arm64.iso \
  --output /mnt/c/GitHub/tmp/ubuntu-26.04-offline-arm64-v9.iso \
  --mde-onboarding-file /mnt/c/GitHub/tmp/mdatp_onboard.json \
  --himmelblau-domain contoso.com
```

The builder detects architecture from ISO metadata, not the filename. No
architecture flag is needed. The host can use either architecture; the builder
does not execute target binaries. Each output retains its source architecture;
this is not a combined image. Review [ARM64 support](arm64-support.md).

## What the builder checks

The builder validates the source ISO and JSON, downloads and checks the package
bundle, adds installer and first-boot configuration, updates checksums, and
preserves source ISO boot settings. It uses an isolated APT workspace and an
empty installed-package database to collect target dependencies without changing
host repositories or packages.

It simulates installation using only the local bundle, both with an empty
package database and with the source Desktop ISO's actual package database. This
checks dependency completeness and compatibility with the installation media.

The builder refuses to overwrite an existing output file. Keep the printed
SHA-256 hash with deployment records. Keep the output ISO private because it
contains tenant-specific Defender onboarding data.

See [package sources and reusable bundles](package-bundles.md) to reuse downloads.
Next: [install on a machine](install-linux.md).