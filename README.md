# Authenticator — TOTP codes in the Omarchy bar

A bar widget that generates your two-factor codes locally (RFC 6238 TOTP) and
puts them one click from the bar: click the key, read the code, click it to copy.
No phone, no cloud, no network.

```
  ⚿   ← bar widget            ┌───────────────────────────────────────────┐
                              │  Authenticator                            │
                              │  3 ACCOUNTS · LOGIN KEYRING               │
                              │  CODES                        ⛭  + Add    │
                              │  ┌─────────────────────────────────────┐  │
                              │  │ GitHub                    123 456 ✕ │  │
                              │  │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇              │  │
                              │  └─────────────────────────────────────┘  │
                              │  Click to copy · M hides · Esc closes     │
                              └───────────────────────────────────────────┘
```

## Install

Local folder (already the case if you built it here):

```bash
omarchy plugin enable psamoluk.totp --section right
omarchy restart shell
```

From the repository:

```bash
omarchy plugin add https://github.com/paulsamoluk/omarchy-authenticator --enable --yes
```

## Add an account

**From the panel** — click the key, then `Add account`, and paste either form:

- the `otpauth://` URI that sits next to a service's QR code:

  ```
  otpauth://totp/GitHub:you@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&period=30&digits=6
  ```

- or, when the setup page only prints the key in text, the **bare base32 secret**
  plus a name for the account (`JBSWY3DPEHPK3PXP`). Spaces and lower case are
  fine. Bare secrets are added with the defaults services use: 6 digits,
  30-second period, SHA-1.

The panel sends the credential to the helper over **stdin**, so the secret never
appears in a process argument list.

**From the shell**, same thing:

```bash
~/.config/omarchy/plugins/psamoluk.totp/bin/otp add-uri 'otpauth://totp/...'
~/.config/omarchy/plugins/psamoluk.totp/bin/otp add --label GitHub --issuer GitHub --secret JBSWY3DPEHPK3PXP
~/.config/omarchy/plugins/psamoluk.totp/bin/otp list
~/.config/omarchy/plugins/psamoluk.totp/bin/otp copy GitHub      # copies the current code
~/.config/omarchy/plugins/psamoluk.totp/bin/otp remove GitHub
```

`--digits`, `--period` and `--algorithm` (SHA1/SHA256/SHA512) are accepted on
`add`, and are read from the URI when using `add-uri`.

Optionally put the helper on `PATH`:
`ln -s ~/.config/omarchy/plugins/psamoluk.totp/bin/otp ~/.local/bin/otp`

## What it looks like

The bar shows a key, the same size and weight as its neighbours — no countdown
in the bar, nothing to misread at a glance. The panel drops out of the bar
**directly under that icon** and opens on a ring around the key carrying the
soonest code's countdown, then one card per account: label and issuer on the
left, the code in large type on the right, and a fuse along each card's bottom
edge that burns down as the code expires.

Colour is used for exactly two states, so a glance is enough:

- **accent** — this code changes in five seconds or less (ring, fuse and the
  seconds count turn accent), or you just copied it (card outline, check glyph,
  code tint for ~1.4 s).
- everything else stays in the theme's foreground at varying opacity.

Hovering a card lifts it and reveals its remove button; the selected card (the
one `↑`/`↓` and `Enter` act on) gets a wash from its accent edge. Codes fade in
as they roll, and the whole countdown moves five times a second instead of
stepping once per second.

## Master password

Optional, off by default. Set it in the panel — the padlock button in the
toolbar — and the codes stay hidden behind one password entry per session:

- The prompt appears the **first time you open the panel in a shell session**;
  unlocking holds for the rest of that session.
- It **re-locks after 15 minutes without use** (`lockMinutes` on the widget's
  `shell.json` entry changes that), and "Lock now" in the same card locks it
  immediately.
- While locked the widget generates no codes at all — the helper is not asked
  for them.
- Forgotten it? `rm ~/.local/share/psamoluk.totp/lock.json` clears the gate.
  That is also why this is a **screen lock, not encryption**: the secrets stay
  in your login keyring, and anything that can read the keyring (your shell,
  `bin/otp list`) can still read them. What it stops is someone walking up to
  your unlocked desktop and reading codes off the panel.
- The password is stored as PBKDF2-SHA256 (300k iterations, random salt) in
  `~/.local/share/psamoluk.totp/lock.json`, mode 0600, never in argv.

## Where the secrets live

- **Login keyring by default** (`secret-tool`, service `psamoluk.totp`, one item
  per account, labelled `omarchy-totp: <account>`). The item is cleared when you
  remove the account.
- `~/.local/share/psamoluk.totp/accounts.json` holds **metadata only** — labels,
  issuer, digits, period, algorithm — `0600`, no secrets, no codes.
- If no keyring backend answers (locked keyring, no D-Bus, no `secret-tool`), the
  helper falls back to storing the secret in that same `0600` file and says so in
  its output (`store: file`). Nothing is ever written world-readable.
- Codes are computed on demand and never stored or logged.
- Nothing here talks to the network, and nothing runs as root.

## Keyboard

| key | action |
|---|---|
| `↑` `↓` | move between codes |
| `Enter` | copy the selected code |
| `M` | hide/reveal codes (persisted) |
| `A` | focus the add field |
| `Esc` | close |

Clicking a row copies it: the code goes to the clipboard and is cleared again
after 60 s — but only if the clipboard still holds that code, so something you
copied later is left alone. Set `TOTP_CLIPBOARD_CLEAR` to change the delay.

## Widget settings

Stored inline on the widget's `shell.json` entry:

- `maskCodes` — start with codes hidden (toggle with `M` in the panel).
- `showCountdown` — show the seconds left in the bar next to the key.

## Requirements

- `python3` (stdlib only), `secret-tool` (libsecret) for the keyring path,
  `wl-copy`/`wl-paste` (wl-clipboard) for copy. All are optional except python3:
  without `secret-tool` secrets go to the `0600` file; without `wl-copy` the
  helper prints the code instead of copying it.
- No services, no sudo, no network, no build step.

## Uninstall

```bash
omarchy plugin remove psamoluk.totp --yes
```

Secrets live outside the plugin folder, so they survive the removal on purpose.
To clear them too: remove each account first (`otp remove <label>`), or delete
the keyring items by hand (`secret-tool clear service psamoluk.totp account <id>`)
and `rm -rf ~/.local/share/psamoluk.totp`.

## Verification note

TOTP generation is checked against the RFC 6238 SHA-1, SHA-256 and SHA-512 test
vectors (`94287082`/`46119246`/`90693936` at T=59) before any release.

## License

MIT — see `LICENSE`.
