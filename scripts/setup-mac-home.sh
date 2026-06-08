#!/usr/bin/env bash
# voice-assistant — one-shot dev environment setup for mac-home.
#
# Idempotent: safe to re-run. Skips already-installed components.
#
# Most of this is already installed on Sergey's mac-home as of 2026-06-08
# (Xcode 26.0.1, brew, node, npm, gh, claude-code, xcodebuildmcp). This
# script exists for fresh setups or as a sanity checklist.
#
# Network note: mac-home's ISP blocks several direct outbound paths
# (registry.npmjs.org DNS, github.com:22, custom proxy ports). The script
# assumes either:
#   (a) the proxy chain in docs/mac-home-setup.md is already configured
#       (HTTP_PROXY / HTTPS_PROXY in ~/.zshrc, ~/.npmrc, SSH ProxyJump),
#   (b) or you're on a fresh network without those constraints.
# It does NOT bootstrap the proxy chain — that's manual (creds local).
#
# Prerequisite (manual, before running this script):
#   1. Install Xcode from App Store
#   2. Open Xcode once → accept license → download iOS platform support
#   3. Export DEVELOPER_DIR (recommended over `sudo xcode-select -s …`):
#        echo 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer' >> ~/.zshrc
#        source ~/.zshrc
#
# Then run:
#   chmod +x scripts/setup-mac-home.sh
#   ./scripts/setup-mac-home.sh

set -euo pipefail

log()  { printf "\033[1;34m[setup]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; }

# ---- 0. Sanity: Xcode reachable ----

if [ -z "${DEVELOPER_DIR:-}" ] && ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    err "Neither DEVELOPER_DIR is set nor xcode-select points at Xcode.app."
    err "Set up Xcode first — see prerequisite block in this script."
    exit 1
fi

if xcodebuild -version >/dev/null 2>&1; then
    ok "Xcode active: $(xcodebuild -version | head -1)"
else
    err "xcodebuild not functional. Open Xcode.app once to finalize install."
    exit 1
fi

if xcrun simctl list runtimes 2>/dev/null | grep -q iOS; then
    ok "iOS simulator runtimes present"
else
    warn "No iOS simulator runtime found. Open Xcode → Settings → Platforms → iOS → Get."
fi

# ---- 1. Homebrew ----

if ! command -v brew >/dev/null 2>&1; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH (Apple Silicon)
    if [ -d /opt/homebrew/bin ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        if ! grep -q 'brew shellenv' "${HOME}/.zprofile" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${HOME}/.zprofile"
        fi
    fi
else
    ok "Homebrew: $(brew --version | head -1)"
fi

# ---- 2. CLI tools via brew ----

declare -a brew_tools=(gh node)
for tool in "${brew_tools[@]}"; do
    if brew list "${tool}" >/dev/null 2>&1; then
        ok "${tool}: $(${tool} --version 2>/dev/null | head -1)"
    else
        log "Installing ${tool}..."
        brew install "${tool}"
    fi
done

# ---- 3. Claude Code CLI ----

if command -v claude >/dev/null 2>&1; then
    ok "Claude Code: $(claude --version 2>/dev/null | head -1)"
else
    log "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
fi

# ---- 4. XcodeBuildMCP ----

if command -v xcodebuildmcp >/dev/null 2>&1; then
    ok "XcodeBuildMCP: $(xcodebuildmcp --help 2>&1 | head -1 || echo present)"
else
    log "Installing XcodeBuildMCP..."
    npm install -g xcodebuildmcp
fi

# ---- 5. Verify MCP config presence ----

if [ -f "${HOME}/.claude.json" ] && command -v jq >/dev/null 2>&1; then
    if jq -e '.mcpServers.xcodebuild' "${HOME}/.claude.json" >/dev/null 2>&1; then
        args=$(jq -r '.mcpServers.xcodebuild.args // [] | join(" ")' "${HOME}/.claude.json")
        if [[ "${args}" == *"mcp"* ]]; then
            ok "MCP 'xcodebuild' registered with 'mcp' subcommand"
        else
            warn "MCP 'xcodebuild' present but args is '${args}' — should be [\"mcp\"]"
            warn "Fix: jq '.mcpServers.xcodebuild.args = [\"mcp\"]' ~/.claude.json | sponge ~/.claude.json"
        fi
    else
        warn "MCP 'xcodebuild' NOT registered. See docs/mac-home-setup.md → XcodeBuildMCP setup."
    fi
fi

# ---- 6. Final pointer ----

cat <<'EOF'

────────────────────────────────────────────────────────────
✅ mac-home base toolchain verified.

Next steps (if not done yet):

  1. Network — set up VDS proxy chain (creds are local-only, NOT in repo):
     - HTTP_PROXY/HTTPS_PROXY for claude (alias `claude-ufo` in ~/.zshrc)
     - ~/.npmrc with proxy / https-proxy
     - SSH ProxyJump for github.com in ~/.ssh/config

     See docs/mac-home-setup.md → "Network constraint".

  2. Login:
       claude-ufo /login

  3. Start project session:
       cd ~/projects/voice-assistant && claude-ufo

────────────────────────────────────────────────────────────
EOF
