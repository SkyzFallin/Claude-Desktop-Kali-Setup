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

# Work around an upstream bug in mcp-kali-server: CommandExecutor.execute() was
# changed to reject list commands (and left a dead `cmd_args = shlex.split(...)`
# line), but health_check and every tool endpoint still pass lists. The result is
# "CommandExecutor expects a string, but got list" for tool detection AND every
# scan. Removing the guard restores the original behavior (lists run shell=False,
# strings run shell=True). Idempotent; makes a .bak and validates syntax first.
SERVER_PY="/usr/share/mcp-kali-server/server.py"
if [[ -f "$SERVER_PY" ]]; then
    echo "[*] Patching mcp-kali-server CommandExecutor (upstream list-command bug)..."
    sudo python3 - "$SERVER_PY" <<'PY'
import sys, ast, shutil
p = sys.argv[1]
lines = open(p).read().split("\n")
out, removed, i = [], 0, 0
while i < len(lines):
    s = lines[i].strip()
    if s == "if not isinstance(self.command, str):":
        i += 1; removed += 1
        if i < len(lines) and lines[i].strip().startswith("raise ValueError"):
            i += 1; removed += 1
        if i < len(lines) and lines[i].strip() == "":
            i += 1
        continue
    if s == "cmd_args = shlex.split(self.command)":
        i += 1; removed += 1
        continue
    out.append(lines[i]); i += 1
if removed == 0:
    print("[*] mcp-kali-server already patched or pattern absent; no change.")
    sys.exit(0)
new = "\n".join(out)
ast.parse(new)  # validate before writing
shutil.copy(p, p + ".bak")
open(p, "w").write(new)
print(f"[+] Patched {p} (removed {removed} lines); backup at {p}.bak")
PY
fi

# The Kali MCP server's health check execs the `which` binary (shell=False) to
# detect tools. Newer debianutils (as tracked by rolling Kali) drops standalone
# /usr/bin/which — it survives only as a shell builtin, which subprocess can't
# exec — so the server falsely reports every tool as missing. Restore the binary
# only if it's actually gone; the provider is 'gnu-which' on newer releases and
# 'which' on some, so try both.
if [[ ! -x /usr/bin/which ]] && ! command -v which >/dev/null 2>&1; then
    echo "[*] Restoring the 'which' binary (needed by the MCP server health check)..."
    sudo apt install -y which 2>/dev/null \
        || sudo apt install -y gnu-which 2>/dev/null \
        || echo "[!] Could not install a 'which' binary; the MCP server may falsely report tools as missing."
fi

# The Kali MCP server drives these CLI tools; a lean Kali install (kali-linux-core)
# ships without them, which makes the server warn "Missing tools" at startup.
echo "[*] Installing essential Kali tools used by the MCP server..."
sudo apt install -y nmap nikto gobuster dirb \
    || echo "[!] Some Kali tools could not be installed (need Kali repos); the MCP server will warn about missing tools."

# The filesystem MCP server runs via npx, which a fresh Kali box lacks (no Node
# by default). Install Node.js/npm, then resolve npx. We only write a server
# block when its command actually resolves, so the config never contains an
# entry that can't spawn.
if ! command -v npx >/dev/null 2>&1; then
    echo "[*] Installing Node.js/npm (needed by the filesystem MCP server)..."
    sudo apt install -y nodejs npm 2>/dev/null || true
fi
NPX_BIN="$(command -v npx || true)"
MCP_BRIDGE_BIN="$(command -v mcp-server || true)"

MCP_BLOCKS=()
if [[ -n "$NPX_BIN" ]]; then
    MCP_BLOCKS+=("    \"filesystem\": {
      \"command\": \"$NPX_BIN\",
      \"args\": [\"-y\", \"@modelcontextprotocol/server-filesystem\", \"$HOME\"]
    }")
else
    echo "[!] 'npx' not found — omitting the filesystem MCP server entry."
    echo "    Install nodejs/npm and rerun, or add the block manually."
fi
if [[ -n "$MCP_BRIDGE_BIN" ]]; then
    MCP_BLOCKS+=("    \"kali-mcp-server\": {
      \"command\": \"$MCP_BRIDGE_BIN\",
      \"args\": [\"--server\", \"http://127.0.0.1:5000\"],
      \"description\": \"Kali MCP Server\",
      \"timeout\": 300
    }")
else
    echo "[!] 'mcp-server' bridge not found on PATH — omitting the kali-mcp-server entry."
    echo "    Install mcp-kali-server from the Kali repos and rerun, or add the block manually."
fi

# Join the resolved blocks with commas (handles 0, 1, or 2 blocks — valid JSON).
MCP_JSON=""
for idx in "${!MCP_BLOCKS[@]}"; do
    if [[ $idx -gt 0 ]]; then
        MCP_JSON+=",
"
    fi
    MCP_JSON+="${MCP_BLOCKS[$idx]}"
done

echo "[*] Configuring MCP servers..."
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << EOF
{
  "mcpServers": {
$MCP_JSON
  }
}
EOF

echo "[*] Installing launcher + desktop shortcut..."
# Launcher script (starts the Kali API server if needed, then Claude Desktop).
LAUNCHER_DIR="$HOME/.local/bin"
LAUNCHER="$LAUNCHER_DIR/claude-kali-launch"
mkdir -p "$LAUNCHER_DIR"
cp "$SCRIPT_DIR/scripts/claude-kali-launch.sh" "$LAUNCHER"
chmod +x "$LAUNCHER"

# Desktop entry pointing at the launcher (Exec must be an absolute path).
DESKTOP_ENTRY="[Desktop Entry]
Type=Application
Version=1.0
Name=Claude Desktop (Kali MCP)
Comment=Start the Kali MCP API server, then launch Claude Desktop
Exec=$LAUNCHER
Icon=claude-desktop-unofficial
Terminal=false
Categories=Development;Utility;
StartupNotify=true"

# App-menu copy.
APP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR"
printf '%s\n' "$DESKTOP_ENTRY" > "$APP_DIR/claude-desktop-kali.desktop"
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$APP_DIR" 2>/dev/null || true

# Desktop copy (must be executable; some desktops also need it marked trusted).
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
mkdir -p "$DESKTOP_DIR"
DESKTOP_SHORTCUT="$DESKTOP_DIR/claude-desktop-kali.desktop"
printf '%s\n' "$DESKTOP_ENTRY" > "$DESKTOP_SHORTCUT"
chmod +x "$DESKTOP_SHORTCUT"
# GNOME/Nautilus: mark the launcher trusted so it runs on double-click.
command -v gio >/dev/null 2>&1 \
    && gio set "$DESKTOP_SHORTCUT" metadata::trusted true 2>/dev/null || true

echo "[+] Installation complete."
echo "    Package signed & verified with our key ($CLAUDE_GNUPGHOME)."
echo "    A 'Claude Desktop (Kali MCP)' shortcut is on your Desktop and in the app menu."
echo "    It starts the Kali API server (if needed), then launches Claude Desktop."
echo "    To launch manually:  $LAUNCHER"
