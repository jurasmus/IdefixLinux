# Onboard an existing installation

[Overview and quick start](../README.md)

For an existing Ubuntu 26.04 amd64 or arm64 machine, run onboarding instead of
building an ISO. Retain the repository's `scripts/` and `compliance/` layout and
run from the root. The online bootstrap still depends on working upstream
repository metadata; prefer an [offline bundle](package-bundles.md) while
Nightly metadata is broken:

```bash
sudo bash scripts/onboard-linux.sh \
  --mde-onboarding-file /path/to/private/mdatp_onboard.json \
  --himmelblau-domain contoso.com \
  --package-directory /path/to/onboarding-packages
```

Use `--skip-himmelblau` to install Defender only. Enabling Himmelblau changes
PAM/NSS; retain a working local administrator session while testing.

The offline helper selects bundled maintainer conffiles with `--force-confnew`.
Do not treat it as a way to preserve customized configuration on an existing
deployment. Review and back up configuration before applying it.

This alternative does not run the full ISO workflow's desktop cleanup and
installer configuration. Follow [verification](verify-setup.md) and validate
[sign-in and enrollment](entra-sign-in.md) separately.