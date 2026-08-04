# Cloudyy encrypt script — contract (checklist)

Future `cloudyy-encrypt` (ISO + existing-system) must:

1. Collect **one** passphrase → set LUKS + user + sudo + GNOME Keyring identically
2. Write `~/.local/share/cloudyy/keyring-unlock.cred` (mode `600`) with that passphrase
3. Call `cloudyy-plymouth-setup` (theme, `encrypt`/`plymouth`/`cloudyy-coldboot` hooks, initramfs rebuild)
4. Run from ISO install **and** an already-built system; warn + require `YES` before destructive disk steps
5. Be idempotent where possible (overwrite cred, re-run plymouth setup; do not reformat LUKS unless asked)

Out of scope here: TPM/FIDO, Plymouth theme implementation, ISO UI.
