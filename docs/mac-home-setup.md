# mac-home dev setup

> Workflow split: voice client developed on **mac-home** (full Xcode +
> XcodeBuildMCP), voice backend developed on **VDS** (Hummingbird service
> deployed there). Single GitHub repo, two cwd-keyed Claude memory trees,
> coordinated through git commits and cross-linked memory.

## Why this split

| | Client (iOS app + Mac dev) | Backend (Hummingbird) |
|--|--|--|
| Where lives | mac-home `~/projects/voice-assistant/` | VDS `/root/projects/voice/` |
| Deps | Xcode 16+, WhisperKit, AVFoundation, SwiftUI | Hummingbird 2, swift-nio, systemd unit |
| Build | `xcodebuild` via XcodeBuildMCP | `swift build` over SSH |
| Test loop | iOS simulator screenshot + tap | `swift test` |
| Cannot run on VDS | iOS app requires macOS / Xcode | — |
| Cannot run on mac-home | systemd service deploy | — |

Both machines clone `flyer2001/voice-assistant`. Source-of-truth is GitHub.

## mac-home prerequisites

1. **Xcode 16+** from App Store (~10 GB download, requires Apple ID)
2. After install — open Xcode once to accept license + download iOS
   platform support
3. Make Xcode the active developer dir:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
4. Optional: Apple Developer team account for distribution (free tier
   sufficient for sideload to own devices)

## Run setup script

After cloning the repo on mac-home:

```bash
cd ~/projects/voice-assistant
./scripts/setup-mac-home.sh
```

Installs (idempotent — safe to re-run):
- Homebrew (if missing)
- `gh` CLI (GitHub auth, releases)
- `node` (XcodeBuildMCP runtime)
- XcodeBuildMCP globally via npm

## Register XcodeBuildMCP with Claude

Inside the repo dir, run:

```bash
claude mcp add xcodebuild -- npx -y xcodebuildmcp
```

OR edit `~/.claude.json` and add under `mcpServers`:

```json
"xcodebuild": {
  "command": "npx",
  "args": ["-y", "xcodebuildmcp"]
}
```

Restart Claude session. Verify:

```bash
claude mcp list
```

`xcodebuild` should appear with status `connected`.

## What XcodeBuildMCP gives me

| Capability | How I'll use it |
|------------|-----------------|
| `build_workspace` / `build_project` / `build_swift_package` | Compile iOS app target before each test cycle |
| `test_workspace_macos` / `test_workspace_simulator` | Run `XCTest` / Swift Testing suites — both on Mac and in simulator |
| `list_simulators` + `boot_simulator` | Pick an iPhone 15/16 simulator, boot it |
| `install_app_simulator` + `launch_app_simulator` | Deploy the freshly built `.app` |
| `screenshot_simulator` | Capture UI for visual verification (hold-to-speak button, bubble state) |
| `get_simulator_logs` | Pull console logs / NSLog after a test run |
| `tap_at_coordinates` + `swipe_simulator` | Simulate user taps (hold-to-speak interaction) — important for v0.1 manual E2E |

## Memory tree split

Each machine's Claude session has its own cwd-keyed memory tree:

| Machine | Memory path |
|---------|-------------|
| VDS | `~/.claude/projects/-root-projects-voice/memory/` |
| mac-home | `~/.claude/projects/-Users-flyer2001-projects-voice-assistant/memory/` |

Decisions made on one side that matter to the other live in `project-*.md`
or `reference-*.md` memories — they get duplicated on the other side
(short pointer note). Source of truth for cross-cutting decisions is the
repo (TASKS.md, VISION.md, CLAUDE.md, this doc).

When starting a mac-home Claude session for the first time, seed it by
asking it to read this file + CLAUDE.md + .claude/TESTING.md + .claude/TASKS.md.

## Backend dev (VDS) — workflow

Stays as-is:
- `cd /root/projects/voice` (note: local dir name still `voice`, cosmetic
  mismatch with repo name `voice-assistant` — kept to avoid memory-tree
  re-keying)
- `swift build` / `swift test` for backend target (once `backend/` exists
  in v0.1)
- Deploy to systemd via existing VDS tooling

## Common pitfalls

- **`xcodebuild: tool requires Xcode`** — Command Line Tools is active,
  not Xcode. Fix: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- **`No simulators available`** — open Xcode → Settings → Platforms →
  iOS → Get (downloads simulator runtime).
- **`npm: command not found` after brew install** — open new shell or
  `source ~/.zprofile`.
- **Claude doesn't see xcodebuildmcp** — restart claude session after
  `claude mcp add`, MCPs load on startup.
