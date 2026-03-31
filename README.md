<p align="center">
  <img src="banner.svg" alt="Claude Desktop Kali Setup Banner" width="100%"/>
</p>

![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Kali%20%7C%20Debian%20%7C%20Ubuntu-c586c0?style=flat-square&logo=linux&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)
![Author](https://img.shields.io/badge/Author-SkyzFallin-ce9178?style=flat-square&logo=github&logoColor=white)

# claude-desktop-kali-setup

One-command installer for Claude Desktop + MCP servers on Kali/Debian/Ubuntu.

**Author:** [SkyzFallin](https://github.com/SkyzFallin)

## What It Does

The install script:

- Adds the Claude Desktop APT repository and GPG key
- Installs `claude-desktop` and `mcp-kali-server`
- Configures MCP servers (filesystem + Kali MCP) in `~/.config/Claude/claude_desktop_config.json`

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
