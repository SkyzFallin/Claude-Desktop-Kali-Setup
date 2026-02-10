#!/usr/bin/env bash
set -euo pipefail

# install-claude-desktop.sh — Install Claude Desktop + MCP servers on Kali/Debian/Ubuntu
# Author: SkyzFallin (https://github.com/SkyzFallin)
# Usage: sudo ./install-claude-desktop.sh
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

echo "[*] Adding Claude Desktop GPG key..."
curl -fsSL https://aaddrick.github.io/claude-desktop-debian/KEY.gpg \
    | gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg

echo "[*] Adding APT repository..."
echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] https://aaddrick.github.io/claude-desktop-debian stable main" \
    > /etc/apt/sources.list.d/claude-desktop.list

echo "[*] Updating package lists..."
apt update -qq

echo "[*] Installing claude-desktop and mcp-kali-server..."
apt install -y claude-desktop mcp-kali-server

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
echo "    To use:"
echo "      1. Start the Kali API server:  kali-server-mcp"
echo "      2. Launch Claude Desktop:      claude-desktop"
