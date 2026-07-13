<p align="center">
  <img src="banner.svg" alt="Claude Desktop Kali Setup Banner" width="100%"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white" alt="Bash"/>
  <img src="https://img.shields.io/badge/Platform-Kali%20%7C%20Debian%20%7C%20Ubuntu-c586c0?style=flat-square&logo=linux&logoColor=white" alt="Platform"/>
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License"/>
  <img src="https://img.shields.io/badge/Author-SkyzFallin-ce9178?style=flat-square&logo=github&logoColor=white" alt="Author"/>
</p>

# claude-desktop-kali-setup

One-command installer for Claude Desktop + MCP servers on Kali/Debian/Ubuntu.

**Author:** [SkyzFallin](https://github.com/SkyzFallin)

## What It Does

The install script:

- Generates **our own** GPG signing keypair (no third-party key pulled from GitHub)
- Builds the `claude-desktop` `.deb` **from source** ([aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian))
- Signs the built package with **our key** and verifies the signature before installing
- Installs `claude-desktop` and `mcp-kali-server`
- Configures MCP servers (filesystem + Kali MCP) in `~/.config/Claude/claude_desktop_config.json`

## Package Signing — Our Own PKI

All signing and verification uses a keypair **we generate and control**. No
third-party PKI is involved at any point:

- `scripts/generate-signing-key.sh` creates a fresh ed25519 signing keypair
  (stored in `/etc/claude-desktop/signing-gnupg`) and exports the public key to
  `claude-desktop-signing.pub.asc`.
- The installer builds the `.deb` locally, signs it with that key, and refuses
  to install unless the signature verifies.
- No third-party APT repository or GPG key is ever added to the system. The
  aaddrick `KEY.gpg` that older setups pulled from GitHub is **not** used.

### Where aaddrick fits in

[aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian)
supplies only the **build scripts** — the code that repackages Anthropic's
official installer into a `.deb`. That is a source-code dependency, not a
trust/PKI dependency:

- None of aaddrick's GPG keys are imported or trusted.
- Inside those build scripts, the download of Anthropic's installer is verified
  by SHA-256 checksum, not by any third-party key.

You can (re)generate the key on its own:

```bash
CLAUDE_GNUPGHOME=~/.claude-desktop-signing ./scripts/generate-signing-key.sh
```

## Quick Start

```bash
git clone https://github.com/SkyzFallin/claude-desktop-kali-setup.git
cd claude-desktop-kali-setup
sudo ./install-claude-desktop.sh
```

## After Installation

1. Start the Kali API server: `kali-server-mcp`
2. Launch Claude Desktop: `claude-desktop`

## Sources

- [claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) — Debian packaging for Claude Desktop
- [mcp-kali-server](https://www.kali.org/tools/mcp-kali-server/) — Kali MCP server for Claude

## License

MIT
