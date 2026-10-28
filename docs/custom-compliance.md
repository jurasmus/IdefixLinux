# Intune custom compliance

[Overview and quick start](../README.md) | [Local verification](verify-setup.md)

To report this example's local health checks through Intune:

1. In the Intune admin center, add
   [compliance/compliance.sh](../compliance/compliance.sh) as a Linux discovery
   script. Microsoft's Linux discovery workflow runs in the signed-in user's
   context, not root. Test discovery without sudo; root-only local diagnostics
   do not prove Intune can read the same settings. Himmelblau's execution path
   can differ, so validate the context used by your enrollment implementation.
2. Create or edit a Linux compliance policy and enable **Custom Compliance**.
3. Select the discovery script and upload
   [compliance/rules.json](../compliance/rules.json) as its rules file.
4. Assign the policy to a small pilot group and confirm results in Intune.

If you intentionally omit Himmelblau, remove the `HimmelblauInstalled` and
`IntuneEnrollmentCompleted` rules before using the rules file.

The discovery script and rules must remain aligned: every rules `SettingName`
must match a reported JSON property. Successful local checks are not a
substitute for portal enrollment, policy evaluation, or Conditional Access
validation. See [sign-in and enrollment](entra-sign-in.md) and
[ARM64 support limitations](arm64-support.md).