# Local administration and device names

[Overview and quick start](../README.md)

## Administrator access

Himmelblau adds authenticated users to `himmelblau-users`. The validated sudoers
rule `%himmelblau-users ALL=(ALL:ALL) ALL` grants that group full local sudo
access. There is no `NOPASSWD` rule and no automatic root login.

All mapped users in this local group are administrators; this is not an
administrator-only Entra group policy. Approve this privilege model before
rollout. Sudo authenticates through PAM; test expected password/PIN/MFA behavior
with your tenant and package version. After signing in:

```bash
id
sudo -l
sudo whoami
```

## Provisional and personalized hostnames

During installation, each device gets a random identifier and a provisional
name such as `ubuntu-a1b2c3d4`, so first boot and early enrollment do not use
`localhost`. An optional PAM session hook personalizes the name after the first
successful Entra login, for example `ubuntu-alex-a1b2c3d4`. The suffix reduces
collisions for users with the same first name or multiple machines.

The first name comes from the NSS display name, falling back to the first part
of the UPN. It is normalized to a bounded ASCII hostname.

The hook is restricted to login/SSH/GDM sessions and the configured Entra UID
range. Sudo sessions, local system users, and subsequent users do not rename the
machine. It updates the local hostname and `127.0.1.1` hosts entry and configures
cloud-init to preserve the name. Failure does not deny login and can be retried
at a later successful login. The success marker is
`/var/lib/linux-onboarding/hostname-set`.

A local administrator can subsequently choose a different name:

```bash
sudo hostnamectl set-hostname NEW-NAME
```

Local renaming does not guarantee immediate renaming of a registered
Entra/Intune/Defender object. Portals may retain the provisional name initially;
verify inventory synchronization and use the supported portal rename process
where necessary. The script adds no Graph permissions or cloud-device renaming
API calls.