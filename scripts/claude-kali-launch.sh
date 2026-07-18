#!/usr/bin/env bash
# claude-kali-launch — start the Kali MCP API server (if it isn't already up),
# then launch Claude Desktop.
#
# Installed to ~/.local/bin and wired to a desktop shortcut by
# install-claude-desktop.sh. Safe to run repeatedly: it won't start a second
# API server if one is already listening.

set -u

API_CMD="kali-server-mcp"            # Kali Flask API server (binds 127.0.0.1:5000)
APP_CMD="claude-desktop-unofficial"  # Claude Desktop binary (upstream name)
API_HOST="127.0.0.1"
API_PORT="5000"
LOG="${TMPDIR:-/tmp}/kali-server-mcp.log"

# Returns success if something is already listening on the API port.
# Uses bash's /dev/tcp so it needs no external tools (ss/netstat/lsof).
port_open() { (exec 3<>"/dev/tcp/${API_HOST}/${API_PORT}") 2>/dev/null; }

if port_open; then
    echo "[*] Kali MCP API server already listening on ${API_HOST}:${API_PORT}."
elif ! command -v "$API_CMD" >/dev/null 2>&1; then
    echo "[!] '$API_CMD' not found — is mcp-kali-server installed? Launching Claude anyway." >&2
else
    echo "[*] Starting Kali MCP API server (logging to ${LOG})..."
    nohup "$API_CMD" >"$LOG" 2>&1 &
    # Wait up to ~15s for it to begin listening so Claude's MCP bridge can connect.
    for _ in $(seq 1 30); do
        port_open && break
        sleep 0.5
    done
    port_open \
        && echo "[+] API server is up on ${API_HOST}:${API_PORT}." \
        || echo "[!] API server did not come up on ${API_HOST}:${API_PORT}; see ${LOG}." >&2
fi

echo "[*] Launching Claude Desktop..."
exec "$APP_CMD" "$@"
