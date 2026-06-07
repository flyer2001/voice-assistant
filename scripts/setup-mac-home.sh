#!/usr/bin/env bash
# voice-assistant — one-shot dev environment setup for mac-home.
#
# Prerequisite (manual, before running this script):
#   1. Install Xcode from App Store (10+ GB download, requires Apple ID)
#   2. Open Xcode once to accept license + install platform support
#   3. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#
# Then run this script:
#   chmod +x scripts/setup-mac-home.sh
#   ./scripts/setup-mac-home.sh
#
# Idempotent: safe to re-run. Skips already-installed components.

set -euo pipefail

log() { printf "\033[1;34m[setup]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; }

# ---- 0. Sanity: Xcode installed ----

if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    err "Xcode.app is not the active developer directory."
    err "Install Xcode from App Store first, then run:"
    err "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    err "Currently selected: $(xcode-select -p 2>/dev/null || echo 'nothing')"
    exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    err "xcodebuild not functional. Open Xcode.app once to finalize install."
    exit 1
fi

log "Xcode active: $(xcodebuild -version | head -1)"

if ! xcrun simctl list devices available >/dev/null 2>&1; then
    warn "simctl available but no simulators. iOS Simulator runtime may not be installed."
    warn "In Xcode: Settings → Platforms → iOS → Get."
fi

# ---- 1. Homebrew ----

if ! command -v brew >/dev/null 2>&1; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for this shell + future shells (Apple Silicon)
    if [ -d /opt/homebrew/bin ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        if ! grep -q 'brew shellenv' "${HOME}/.zprofile" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${HOME}/.zprofile"
        fi
    fi
else
    log "Homebrew already installed: $(brew --version | head -1)"
fi

# ---- 2. CLI tools via brew ----

declare -a brew_tools=(gh node)
for tool in "${brew_tools[@]}"; do
    if brew list "${tool}" >/dev/null 2>&1; then
        log "${tool}: already installed"
    else
        log "Installing ${tool}..."
        brew install "${tool}"
    fi
done

# ---- 3. XcodeBuildMCP (npm global) ----

if npm list -g --depth=0 2>/dev/null | grep -q xcodebuildmcp; then
    log "XcodeBuildMCP: already installed"
else
    log "Installing XcodeBuildMCP..."
    npm install -g xcodebuildmcp
fi

# ---- 4. Print MCP config snippet ----

cat <<'EOF'

────────────────────────────────────────────────────────────
✅ mac-home setup complete.

Next: add XcodeBuildMCP to Claude Code config.

In a Claude session running on mac-home (cd to voice-assistant repo first):

  claude mcp add xcodebuild -- npx -y xcodebuildmcp

OR edit ~/.claude.json manually and add under "mcpServers":

  "xcodebuild": {
    "command": "npx",
    "args": ["-y", "xcodebuildmcp"]
  }

Then restart Claude and verify:

  claude mcp list

If XcodeBuildMCP appears, you can now ask Claude to build, run tests,
boot simulators, and capture screenshots.

See docs/mac-home-setup.md for the full workflow split (client on
mac-home, backend on VDS).
────────────────────────────────────────────────────────────
EOF
