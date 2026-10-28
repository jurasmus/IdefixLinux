# Entra sign-in, PIN and enrollment

[Overview and quick start](../README.md) | [Installation](install-linux.md)

## First sign-in and Hello PIN

The generated Himmelblau configuration explicitly enables Hello enrollment and
the experimental MFA flow used by Hello authentication, with a six-character
minimum PIN. After initial successful online Entra authentication, Himmelblau
can prompt the user to create a local Hello PIN.

On supported subsequent local sign-ins, the user can authenticate with their
UPN and PIN instead of repeating password-and-MFA authentication. Selecting a
cached account supplies its username; otherwise enter the full UPN. Initial
sign-in can require the user's password and tenant MFA.

The Hello MFA flow is documented by Himmelblau as experimental. Conditional
Access and tenant authentication policy can still require additional
authentication; a local PIN does not override those policies. Test PIN setup
and subsequent login with a pilot account on the actual hardware and Himmelblau
package version before broad deployment.

For previously installed machines, see [enable remembered users](remembered-users.md).

## Enrollment and device identity

Defender is configured with the tenant onboarding JSON during installation.
Intune enrollment is a separate operation that Himmelblau can initiate after
authentication. A successful installation or login does not guarantee
enrollment: licensing, device registration settings, Conditional Access, network
access, and tenant policy must permit it.

Confirm the device appears in the Defender and Intune portals and verify its
Entra identity. Installing Intune Portal does not itself enroll the device. Do
not start another enrollment without checking the existing identity first.

Each machine must create its own device identity. Do not capture and redeploy a
disk image after a machine has registered with Entra or Intune.

Use the [rollout checklist](rollout-checklist.md) to validate the full flow.