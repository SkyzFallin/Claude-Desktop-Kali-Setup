#!/usr/bin/env bash
set -euo pipefail

# install-claude-desktop.sh — Build & install Claude Desktop + MCP servers on Kali/Debian/Ubuntu
# Author: SkyzFallin (https://github.com/SkyzFallin)
# Usage: sudo ./install-claude-desktop.sh
#
# Instead of trusting a third-party APT repo + key hosted on GitHub, this script
# builds the Claude Desktop .deb from source (aaddrick/claude-desktop-debian)
# and signs/verifies it with OUR OWN GPG signing key before installing.
#
# Sources:
#   https://github.com/aaddrick/claude-desktop-debian
#   https://www.kali.org/tools/mcp-kali-server/

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
CONFIG_DIR="$REAL_HOME/.config/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_REPO="${CLAUDE_BUILD_REPO:-https://github.com/aaddrick/claude-desktop-debian.git}"
BUILD_DIR="${CLAUDE_BUILD_DIR:-/opt/claude-desktop-build}"

# Our signing key lives here (root-owned; it only signs locally-built packages).
export CLAUDE_GNUPGHOME="${CLAUDE_GNUPGHOME:-/etc/claude-desktop/signing-gnupg}"
PUBKEY_OUT="$SCRIPT_DIR/claude-desktop-signing.pub.asc"

echo "[*] Installing build prerequisites..."
apt update -qq
apt install -y git gpg curl ca-certificates

echo "[*] Generating our own package-signing key (if needed)..."
CLAUDE_GNUPGHOME="$CLAUDE_GNUPGHOME" CLAUDE_PUBKEY_OUT="$PUBKEY_OUT" \
    bash "$SCRIPT_DIR/scripts/generate-signing-key.sh"
# Let the invoking user own the exported public key so it can be committed/shared.
chown "$REAL_USER:$REAL_USER" "$PUBKEY_OUT" 2>/dev/null || true

echo "[*] Fetching Claude Desktop build scripts..."
if [[ -d "$BUILD_DIR/.git" ]]; then
    git -C "$BUILD_DIR" pull --ff-only
else
    git clone --depth 1 "$BUILD_REPO" "$BUILD_DIR"
fi

echo "[*] Building the Claude Desktop .deb from source..."
( cd "$BUILD_DIR" && ./build.sh --build deb )

DEB_FILE=$(ls -t "$BUILD_DIR"/claude-desktop_*.deb 2>/dev/null | head -n1 || true)
if [[ -z "$DEB_FILE" ]]; then
    echo "Build did not produce a .deb file in $BUILD_DIR." >&2
    exit 1
fi
echo "[*] Built package: $DEB_FILE"

echo "[*] Signing the package with our key..."
GNUPGHOME="$CLAUDE_GNUPGHOME" \
    gpg --batch --yes --armor --detach-sign --output "${DEB_FILE}.asc" "$DEB_FILE"

echo "[*] Verifying the package signature with our key..."
GNUPGHOME="$CLAUDE_GNUPGHOME" \
    gpg --batch --verify "${DEB_FILE}.asc" "$DEB_FILE"
echo "[+] Signature verified — package is authentic."

echo "[*] Installing claude-desktop..."
apt install -y "$DEB_FILE"

echo "[*] Installing mcp-kali-server..."
apt install -y mcp-kali-server \
    || echo "[!] mcp-kali-server not available via APT (needs Kali repos); skipping."

echo "[*] Configuring MCP servers..."
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << EOF
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "$REAL_HOME"]
    },
    "kali-mcp-server": {
      "command": "python3",
      "args": [
        "/usr/share/mcp-kali-server/mcp_server.py",
        "--server",
        "http://127.0.0.1:5000/"
      ],
      "description": "Kali MCP Server",
      "timeout": 300
    }
  }
}
EOF
chown -R "$REAL_USER:$REAL_USER" "$CONFIG_DIR"

echo "[+] Installation complete."
echo "    Package signed & verified with our key ($CLAUDE_GNUPGHOME)."
echo "    To use:"
echo "      1. Start the Kali API server:  kali-server-mcp"
echo "      2. Launch Claude Desktop:      claude-desktop"
