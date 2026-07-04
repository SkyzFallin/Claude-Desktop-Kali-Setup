#!/usr/bin/env bash
set -euo pipefail

# generate-signing-key.sh — Generate our OWN GPG signing keypair.
#
# This replaces the third-party key we used to pull from GitHub
# (aaddrick.github.io/.../KEY.gpg). We now build Claude Desktop from source and
# sign the resulting package with a keypair we generate and control.
#
# The key is created without a passphrase so it can be used non-interactively
# during automated builds. It only signs locally-built packages, so it is not a
# published identity — keep the private key (in $GNUPGHOME) off shared systems.
#
# Configuration (all optional, via environment variables):
#   CLAUDE_KEY_NAME    Real name on the key      (default below)
#   CLAUDE_KEY_EMAIL   Email/UID on the key       (default below)
#   CLAUDE_GNUPGHOME   Where the keypair lives    (default: ~/.claude-desktop-signing)
#   CLAUDE_PUBKEY_OUT  Where to export the public key (default: repo root)

KEY_NAME="${CLAUDE_KEY_NAME:-Claude Desktop Kali Setup (package signing)}"
KEY_EMAIL="${CLAUDE_KEY_EMAIL:-claude-desktop-kali-signing@localhost}"
GNUPGHOME_DIR="${CLAUDE_GNUPGHOME:-${HOME:-/root}/.claude-desktop-signing}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBKEY_OUT="${CLAUDE_PUBKEY_OUT:-$SCRIPT_DIR/../claude-desktop-signing.pub.asc}"

mkdir -p "$GNUPGHOME_DIR"
chmod 700 "$GNUPGHOME_DIR"
export GNUPGHOME="$GNUPGHOME_DIR"

if gpg --list-secret-keys "$KEY_EMAIL" >/dev/null 2>&1; then
    echo "[*] Signing key for <$KEY_EMAIL> already exists in $GNUPGHOME_DIR"
else
    echo "[*] Generating a fresh GPG signing keypair for <$KEY_EMAIL>..."
    gpg --batch --gen-key <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: $KEY_NAME
Name-Email: $KEY_EMAIL
Expire-Date: 0
%commit
EOF
    echo "[+] Keypair generated."
fi

echo "[*] Exporting public key to $PUBKEY_OUT"
gpg --armor --export "$KEY_EMAIL" > "$PUBKEY_OUT"

echo "[+] Signing key ready. Fingerprint:"
gpg --fingerprint "$KEY_EMAIL"
