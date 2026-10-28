# Remove or retire a device

[Overview and quick start](../README.md)

Offboard Defender using the offboarding package from the Defender portal before
removing `mdatp`. Removing the package alone does not offboard the device from
the service.

Remove or retire the device through your Entra and Intune processes as well.
Reverse Himmelblau PAM/NSS changes only with a working local administrator
session; recovery is machine-specific.

Keep encrypted-device recovery credentials and installation media available.
This ISO creates no local fallback account, so test the recovery path before
removing the authentication components.