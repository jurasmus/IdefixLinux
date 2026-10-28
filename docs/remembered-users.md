# Enable remembered users on an existing machine

[Overview and quick start](../README.md) | [Sign-in behavior](entra-sign-in.md)

The v8 and later login profile enables GDM's remembered-user list. On an older
installation, no reinstall is needed. From a terminal in your signed-in Entra
desktop session, not a root shell, run:

```bash
sudo install -d -m 0755 /etc/dconf/db/gdm.d /etc/dconf/profile
if [ ! -f /etc/dconf/profile/gdm ]; then
  printf 'user-db:user\nsystem-db:gdm\nfile-db:/usr/share/gdm/greeter-dconf-defaults\n' | sudo tee /etc/dconf/profile/gdm >/dev/null
fi
printf '[org/gnome/login-screen]\ndisable-user-list=false\n' | sudo tee /etc/dconf/db/gdm.d/01-entra-login >/dev/null
sudo dconf update
sudo busctl call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts CacheUser s "$(id -un)"
```

The last command explicitly caches the current account through AccountsService;
it should return an object path such as `/org/freedesktop/Accounts/User6000001`.
It does not create a local account, store a password, or change authentication.

Save your work, then reboot normally. Select your account and authenticate as
before. Other cached accounts may also be listed; **Not listed?** remains
available for another user. Enabling this list exposes cached account names at
the login screen. It does not enable automatic login or remove PIN/password and
tenant MFA requirements.

## Troubleshooting and rollback

If caching fails or the account is still absent, keep using the full UPN and
collect the following before changing account files or PAM:

```bash
systemctl status accounts-daemon
sudo journalctl -b -u accounts-daemon
```

To hide the list again, write `disable-user-list=true` to the same settings file,
run `sudo dconf update`, and reboot. Do not restart GDM from an active desktop
session, as doing so terminates the session.