#!/bin/bash
# Called by pam_exec(8) from /etc/pam.d/hyprlock after successful authentication.
# PAM passes the auth token (login password) on stdin via expose_authtok.
# This script uses it to load the SSH key into the persistent agent.

AGENT_SOCK="$HOME/.ssh/ssh-agent.socket"
KEY_FILE="$HOME/.ssh/id_ed25519"

password=""
read -r -t 5 password 2>/dev/null || true

[[ -n "$password" ]] || exit 0
[[ -S "$AGENT_SOCK" ]] || exit 0

# Key already loaded — nothing to do
SSH_AUTH_SOCK="$AGENT_SOCK" timeout 3 /usr/bin/ssh-add -l 2>/dev/null | /usr/bin/grep -q 'SHA256' && exit 0

tmp=$(/usr/bin/mktemp /tmp/.askpass.XXXXXX) || exit 1
/usr/bin/chmod 700 "$tmp"
b64=$(/usr/bin/printf '%s' "$password" | /usr/bin/base64 -w0)
# %%s in the generated script's printf format = literal %s substitution (one %% → one %)
/usr/bin/printf '#!/bin/bash\nprintf "%%s" "$(/usr/bin/base64 -d <<< %s)"\n' "$b64" >"$tmp"

SSH_AUTH_SOCK="$AGENT_SOCK" SSH_ASKPASS="$tmp" SSH_ASKPASS_REQUIRE=force \
  timeout 5 /usr/bin/ssh-add "$KEY_FILE" </dev/null 2>/dev/null || true

/usr/bin/rm -f "$tmp"
exit 0
