### Repository URL

https://github.com/paulsamoluk/omarchy-authenticator

### Category

System

### Tags

Bar, Security, Quickshell

### Maintainer notes

A bar widget plus popout that generates RFC 6238 TOTP codes locally, with an optional master password that encrypts the secrets at rest.

**Dependencies:** `python3` (stdlib only) is required; `gpg` for the encrypted vault; `zbar` (`zbarimg`) only for adding an account from a QR screenshot; `wl-clipboard` for copy; `secret-tool` (libsecret) for keyring storage when no master password is set. Nothing is downloaded or built at install time.

**Privilege boundary:** no sudo, no system service, no daemon, no network requests, no post-install hooks. It is QML loaded inside `omarchy-shell` plus one Python helper invoked on demand.

**What it writes:** `~/.local/share/psamoluk.totp/` (0700) containing `accounts.json` (0600 — labels and TOTP parameters only) and `vault.gpg` (0600, AES-256) when a master password is set; a session key in `$XDG_RUNTIME_DIR/psamoluk.totp/session` (0600, tmpfs, deleted on lock and logout); login-keyring items while no password is set; and the clipboard when a code is clicked. It never touches Omarchy configuration.

**Secret handling:** secrets and master passwords are only ever read from stdin — `--secret` on argv is refused outright because an argument is visible in `ps`. Codes are computed in memory, never logged, and a decoded QR screenshot is deleted immediately after use. No network code exists in the helper.

**Master password (optional):** when set, every secret moves into an AES-256 GPG-symmetric vault and the keyring copy is removed, so without the password there is nothing to decrypt. Unlock holds for the login session; it re-locks after 15 idle minutes or on demand, and a locked helper refuses to produce a code. There is deliberately **no recovery path** — forgetting the password means resetting, which destroys the accounts (stated in the README and in the panel).

**Upgrade path:** an install from the earlier hash-gate build migrates itself on the next unlock — same password, same codes, keyring copy cleared.

**Other:** MIT, `LICENSE` at the repository root, install and removal instructions in the README. `preview.png` is a screenshot of the plugin with three demo accounts (dummy secrets, no real data). Tested on Omarchy 4.0.6 / quickshell 0.3.2; `omarchy plugin validate` passes and the TOTP implementation is checked against the RFC 6238 SHA-1/256/512 vectors in `tests/`.

### Submission checklist

- [X] The repository is public and contains installation and removal instructions.
- [X] I have documented the plugin license and any external dependencies.
- [X] I confirm that I own or have permission to submit this plugin and its preview assets.
- [X] The plugin does not overwrite user configuration without explicit consent.
- [X] I understand that approval is for listing and is not a security review.
