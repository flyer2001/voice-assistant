# mac-home dev setup

> Workflow split: voice client developed on **mac-home** (full Xcode +
> XcodeBuildMCP), voice backend developed on a **dev VDS** (Hummingbird
> service deployed there). Single GitHub repo, two cwd-keyed Claude
> memory trees, coordinated through git commits and cross-linked memory.

## Why this split

| | Client (iOS app + Mac dev) | Backend (Hummingbird) |
|--|--|--|
| Where lives | mac-home `~/projects/voice-assistant/` | VDS `/root/projects/voice/` |
| Deps | Xcode 16+, WhisperKit, AVFoundation, SwiftUI | Hummingbird 2, swift-nio, systemd unit |
| Build | `xcodebuild` via XcodeBuildMCP | `swift build` over SSH |
| Test loop | iOS simulator screenshot + tap | `swift test` |
| Cannot run on VDS | iOS app requires macOS / Xcode | — |
| Cannot run on mac-home | systemd service deploy | — |

Both machines clone `flyer2001/voice-assistant`. Source of truth is GitHub.

## Prerequisites — base macOS

- macOS 14+ on Apple Silicon (M-series)
- Xcode 16+ from App Store (~10 GB DL, ~40 GB after install)
- iOS Simulator runtime (Xcode → Settings → Platforms → iOS → Get)
- `DEVELOPER_DIR` exported in shell — recommended **per-user without sudo**:
  ```bash
  echo 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer' >> ~/.zshrc
  ```
  (Alternative `sudo xcode-select -s ...` works system-wide but needs sudo.)
- License accepted: open Xcode once → accept; that satisfies it.
- Homebrew, `git`, `gh`, `node`, `npm` — install via brew if missing.
- Claude Code CLI: `npm install -g @anthropic-ai/claude-code` (via brew npm).

The repo's `scripts/setup-mac-home.sh` is idempotent and installs only what's
missing.

## Network constraint — ISP blocks direct outbound

Important: on Sergey's home ISP, several direct outbound TCP destinations
are blocked or unreliable from mac-home:
- Custom HTTP-proxy ports (e.g. 8388) to arbitrary public IPs — closed by
  the network path.
- `registry.npmjs.org` — DNS resolution sometimes fails.
- `github.com:22` (SSH) — connection closed mid-handshake.

**Workaround:** route all outbound `claude` / `npm` / `git-over-SSH`
traffic through a proxy running on the dev VDS, reached via a WireGuard
tunnel that already exists between mac-home and the VDS. Direct outbound
HTTPS (browser, `brew`, plain curl) works as normal — only the targets
above need the proxy.

The concrete credentials and IPs are stored **only** in mac-home's local
shell configs and never in this repo. Placeholders below — substitute
the real values from `~/.zshrc` on mac-home.

```
{PROXY_HOST}        — VDS address reachable from mac-home (use the WG IP,
                      e.g. 10.x.x.1, NOT the public IP)
{PROXY_PORT}        — proxy port (e.g. 8388)
{PROXY_USER}:{PROXY_PASS}  — basic-auth credentials from tinyproxy.conf
{VDS_SSH_ALIAS}     — an SSH alias in mac-home's ~/.ssh/config that
                      points to the VDS via the WG IP (NOT public IP)
```

## Wire up the proxy on mac-home

### 1. Claude Code alias

Add to `~/.zshrc`:

```bash
# claude through VDS HTTP-proxy (ISP blocks direct outbound)
alias claude-ufo='HTTP_PROXY="http://{PROXY_USER}:{PROXY_PASS}@{PROXY_HOST}:{PROXY_PORT}" HTTPS_PROXY="http://{PROXY_USER}:{PROXY_PASS}@{PROXY_HOST}:{PROXY_PORT}" claude'
```

Use `claude-ufo` everywhere instead of `claude`. All claude flags work
identically (`claude-ufo -c`, `claude-ufo /login`, etc.).

### 2. npm proxy — permanent

Write `~/.npmrc`:

```
proxy=http://{PROXY_USER}:{PROXY_PASS}@{PROXY_HOST}:{PROXY_PORT}
https-proxy=http://{PROXY_USER}:{PROXY_PASS}@{PROXY_HOST}:{PROXY_PORT}
```

Verify with `npm ping` (should return PONG in <2s).

### 3. SSH `github.com` via VDS ProxyJump

Append to `~/.ssh/config`:

```
Host {VDS_SSH_ALIAS}
    HostName {WG_IP_OF_VDS}
    User root
    IdentityFile ~/.ssh/<your-vds-key>
    StrictHostKeyChecking accept-new

Match host github.com
    ProxyJump {VDS_SSH_ALIAS}
```

Verify: `ssh -T git@github.com` → `Hi flyer2001! You've successfully authenticated…`.

After this, `git clone git@github.com:flyer2001/voice-assistant.git`
works normally.

## Claude OAuth login

From any shell on mac-home (the token persists globally — not cwd-bound):

```bash
claude-ufo /login
```

OAuth flow prints a URL → open in any browser (mac-home or, if SSHed in,
copy URL to your local browser) → complete sign-in → terminal detects the
callback and finishes login.

## XcodeBuildMCP setup

XcodeBuildMCP gives Claude tools to build, run tests, control iOS
simulators, capture screenshots, and tap UI. Install:

```bash
# requires ~/.npmrc with proxy (see above) or env vars
npm install -g xcodebuildmcp
which xcodebuildmcp   # → /opt/homebrew/bin/xcodebuildmcp
xcodebuildmcp --help
```

Register it with Claude Code (note the **`mcp` subcommand** — v2.6+ requires it):

Edit `~/.claude.json`, add to `mcpServers`:

```json
"xcodebuild": {
  "type": "stdio",
  "command": "/opt/homebrew/bin/xcodebuildmcp",
  "args": ["mcp"],
  "env": {
    "INCREMENTAL_BUILDS_ENABLED": "1",
    "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
    "PATH": "/Users/<you>/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  }
}
```

Restart Claude session. Verify by asking Claude inside a session to list
its MCP tools — `xcodebuild` entries should appear.

## End-to-end verification

```bash
cd ~/projects
git clone git@github.com:flyer2001/voice-assistant.git
cd voice-assistant

swift build      # ~30s first time, then incremental
swift test       # should pass PackageSanityTests (2 tests)
claude-ufo       # starts a project session
```

Then in the Claude session ask:

> Прочитай README.md, CLAUDE.md, docs/mac-home-setup.md, .claude/TESTING.md,
> .claude/TASKS.md, MEMORY.md и опиши что увидел. Готова к v0.1 client tickets?

## What XcodeBuildMCP gives me

| Capability | Use |
|------------|-----|
| `build_workspace` / `build_project` / `build_swift_package` | Compile iOS app before each test cycle |
| `test_workspace_macos` / `test_workspace_simulator` | Run XCTest / Swift Testing — Mac + simulator |
| `list_simulators` + `boot_simulator` | Pick iPhone simulator, boot it |
| `install_app_simulator` + `launch_app_simulator` | Deploy freshly built `.app` |
| `screenshot_simulator` | Capture UI (hold-to-speak button, bubble state) |
| `get_simulator_logs` | Pull console / NSLog after a run |
| `tap_at_coordinates` + `swipe_simulator` | Simulate user taps for v0.1 manual E2E |

## Memory tree split

Each machine's Claude session has its own cwd-keyed memory tree:

| Machine | Memory path |
|---------|-------------|
| VDS | `~/.claude/projects/-root-projects-voice/memory/` |
| mac-home | `~/.claude/projects/-Users-<you>-projects-voice-assistant/memory/` |

Decisions made on one side that matter to the other live in `project-*.md`
or `reference-*.md` memories — they get duplicated on the other side
(short pointer note). Source of truth for cross-cutting decisions is the
repo (TASKS.md, VISION.md, CLAUDE.md, this doc).

When starting a mac-home Claude session for the first time, seed it by
asking it to read this file + CLAUDE.md + .claude/TESTING.md +
.claude/TASKS.md + MEMORY.md.

## Backend dev (VDS) — workflow

Stays as-is:
- `cd /root/projects/voice` (note: local dir name still `voice`, cosmetic
  mismatch with repo name `voice-assistant` — kept to avoid memory-tree
  re-keying)
- `swift build` / `swift test` for backend target (once `backend/` exists
  in v0.1)
- Deploy to systemd via existing VDS tooling

## Tripwires — do NOT commit

- Proxy credentials (`{PROXY_USER}`, `{PROXY_PASS}`) are device-local to
  mac-home's `~/.zshrc` / `~/.npmrc`. They must never appear in this repo.
- VDS IPs / WG IPs are private infrastructure. The repo describes the
  pattern, not the values.
- If you accidentally commit any of the above, rotate immediately
  (regenerate basic-auth password in `tinyproxy.conf`, update local configs)
  and rewrite git history.

## Common pitfalls

- **`xcodebuild: tool requires Xcode`** — Command Line Tools is active.
  Fix: export `DEVELOPER_DIR` as shown above, or `sudo xcode-select -s …`.
- **`No simulators available`** — open Xcode → Settings → Platforms →
  iOS → Get.
- **`npm: command not found` after brew install** — open new shell or
  `source ~/.zprofile`.
- **Claude doesn't see xcodebuild MCP** — most common cause: missing
  `mcp` subcommand in `args`. Second cause: claude session needs restart
  after editing `~/.claude.json`.
- **`Proxy CONNECT aborted` from mac-home** — you used the proxy's public
  IP. Use the WG IP. Public IP is for VDS-local traffic only.
- **`git clone` hangs** — SSH to github.com is blocked; ProxyJump via
  VDS isn't configured yet. See "SSH `github.com` via VDS ProxyJump"
  above.
