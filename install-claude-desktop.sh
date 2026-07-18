#!/usr/bin/env bash
set -euo pipefail

# install-claude-desktop.sh — Build & install Claude Desktop + MCP servers on Kali/Debian/Ubuntu
# Author: SkyzFallin (https://github.com/SkyzFallin)
# Usage: ./install-claude-desktop.sh   (as a normal user — NOT with sudo)
#
# Instead of trusting a third-party APT repo + key hosted on GitHub, this script
# builds the Claude Desktop .deb from source (aaddrick/claude-desktop-debian)
# and signs/verifies it with OUR OWN GPG signing key before installing.
#
# The upstream build.sh refuses to run as root, so this script runs as a normal
# user and invokes sudo only for the steps that need it (may prompt for password).
#
# Sources:
#   https://github.com/aaddrick/claude-desktop-debian
#   https://www.kali.org/tools/mcp-kali-server/

if [[ $EUID -eq 0 ]]; then
    echo "Do not run this script as root or with sudo." >&2
    echo "The upstream Claude Desktop build script refuses to run as root." >&2
    echo "Run it as a normal user; sudo is used internally where needed." >&2
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required but not installed." >&2
    exit 1
fi

CONFIG_DIR="$HOME/.config/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_REPO="${CLAUDE_BUILD_REPO:-https://github.com/aaddrick/claude-desktop-debian.git}"
BUILD_DIR="${CLAUDE_BUILD_DIR:-/opt/claude-desktop-build}"

# Our signing key lives here (root-owned; it only signs locally-built packages).
CLAUDE_GNUPGHOME="${CLAUDE_GNUPGHOME:-/etc/claude-desktop/signing-gnupg}"
PUBKEY_OUT="$SCRIPT_DIR/claude-desktop-signing.pub.asc"

echo "[*] Installing build prerequisites..."
sudo apt update -qq
sudo apt install -y git gpg curl ca-certificates

echo "[*] Generating our own package-signing key (if needed)..."
sudo env CLAUDE_GNUPGHOME="$CLAUDE_GNUPGHOME" CLAUDE_PUBKEY_OUT="$PUBKEY_OUT" \
    bash "$SCRIPT_DIR/scripts/generate-signing-key.sh"
# Let the invoking user own the exported public key so it can be committed/shared.
sudo chown "$USER": "$PUBKEY_OUT"

echo "[*] Fetching Claude Desktop build scripts..."
# The build dir must be writable by us; also fix ownership left over from any
# earlier run of this installer under sudo.
sudo mkdir -p "$BUILD_DIR"
sudo chown -R "$USER": "$BUILD_DIR"
if [[ -d "$BUILD_DIR/.git" ]]; then
    git -C "$BUILD_DIR" pull --ff-only
else
    git clone --depth 1 "$BUILD_REPO" "$BUILD_DIR"
fi

echo "[*] Building the Claude Desktop .deb from source..."
# Clear artifacts from previous builds so we only sign/install what this build produces.
rm -f "$BUILD_DIR"/claude-desktop*.deb "$BUILD_DIR"/claude-desktop*.deb.asc
( cd "$BUILD_DIR" && ./build.sh --build deb )

# Upstream renamed the package to claude-desktop-unofficial and may also emit a
# transitional claude-desktop deb that depends on it — collect and install all.
mapfile -t DEB_FILES < <(ls -t "$BUILD_DIR"/claude-desktop*_*.deb 2>/dev/null || true)
if [[ ${#DEB_FILES[@]} -eq 0 ]]; then
    echo "Build did not produce a .deb file in $BUILD_DIR." >&2
    exit 1
fi
echo "[*] Built package(s): ${DEB_FILES[*]}"

for DEB_FILE in "${DEB_FILES[@]}"; do
    echo "[*] Signing ${DEB_FILE##*/} with our key..."
    sudo env GNUPGHOME="$CLAUDE_GNUPGHOME" \
        gpg --batch --yes --armor --detach-sign --output "${DEB_FILE}.asc" "$DEB_FILE"

    echo "[*] Verifying the package signature with our key..."
    sudo env GNUPGHOME="$CLAUDE_GNUPGHOME" \
        gpg --batch --verify "${DEB_FILE}.asc" "$DEB_FILE"
done
echo "[+] Signature(s) verified — package(s) are authentic."

echo "[*] Installing claude-desktop..."
sudo apt install -y "${DEB_FILES[@]}"

echo "[*] Installing mcp-kali-server..."
sudo apt install -y mcp-kali-server \
    || echo "[!] mcp-kali-server not available via APT (needs Kali repos); skipping."

echo "[*] Configuring MCP servers..."
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << EOF
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "$HOME"]
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

echo "[+] Installation complete."
echo "    Package signed & verified with our key ($CLAUDE_GNUPGHOME)."
echo "    To use:"
echo "      1. Start the Kali API server:  kali-server-mcp"
echo "      2. Launch Claude Desktop:      claude-desktop"
