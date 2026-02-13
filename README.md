# copilot-sessions

A session dashboard and manager for [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli). See all your sessions at a glance, focus the right terminal tab, or resume old sessions — from the command line or a macOS menu bar app.

Inspired by [nice-semaphore](https://github.com/nice-computer/nice-semaphore) for Claude Code.

![CLI Screenshot](docs/cli.png)

## Features

- **CLI dashboard** — see all active and recent Copilot sessions at a glance
- **Interactive picker** — select a session to focus its tab or resume it
- **macOS menu bar app** — 🤖 in your menu bar with click-to-focus/resume
- **Terminal agnostic** — extensible adapter layer for Apple Terminal, kitty, iTerm2
- **Auto-detection** — finds the best available terminal emulator

## Requirements

- macOS 13+
- [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
- Python 3.9+
- Swift 5.9+ (for the menu bar app)

## Install

```bash
git clone https://github.com/schlubbi/copilot-sessions.git
cd copilot-sessions
make install
```

This symlinks the CLI to `~/.local/bin/copilot-sessions` and builds the menu bar app.

To make the menu bar app findable via Spotlight:

```bash
ln -sf $(pwd)/CopilotSessions.app ~/Applications/CopilotSessions.app
```

To auto-start on login, add `CopilotSessions.app` in **System Settings → General → Login Items**.

## Usage

### CLI

```bash
# Dashboard of active sessions
copilot-sessions

# Include recent inactive sessions
copilot-sessions --all

# Interactive picker — select to focus or resume
copilot-sessions --pick

# Focus a specific session's tab
copilot-sessions --focus <session-id-prefix>

# Resume an inactive session in a new terminal tab
copilot-sessions --resume <session-id>
```

### Menu Bar App

```bash
make run-menubar
```

The menu bar shows 🤖 with the number of active sessions. Click to see the full list — click a session to focus or resume it, or start a new one.

## Terminal Support

The app auto-detects your terminal and uses the best available integration:

| Terminal | Focus Tab | New Tab | How |
|----------|-----------|---------|-----|
| **Apple Terminal** | ✅ via AppleScript TTY matching | ✅ via System Events | Always available on macOS |
| **kitty** | ✅ via remote control PID matching | ✅ via `kitty @` or direct launch | Needs `allow_remote_control yes` |
| **iTerm2** | ✅ via AppleScript TTY matching | ✅ via AppleScript | Needs iTerm2 installed |

### kitty Setup (optional)

If you use kitty, add to `~/.config/kitty/kitty.conf`:

```
allow_remote_control yes
listen_on unix:/tmp/kitty
```

### Adding a new terminal

Implement the `TerminalAdapter` protocol in `CopilotSessions/Sources/TerminalAdapter.swift`:

```swift
protocol TerminalAdapter {
    var name: String { get }
    func isAvailable() -> Bool
    func focusTab(tty: String) -> Bool
    func launch(command: [String], title: String) -> Bool
}
```

Then add it to `detectTerminalAdapter()`.

## How It Works

```
┌─────────────────────────────────────────────────┐
│                  Data Sources                    │
│                                                  │
│  ps ─────────► running copilot PIDs + TTYs       │
│  lsof ───────► PID → session ID mapping          │
│  ~/.copilot/ ► session metadata (topic, branch)  │
└──────────────────────┬──────────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
     ┌─────▼─────┐         ┌──────▼──────┐
     │    CLI     │         │  Menu Bar   │
     │ dashboard  │         │    App      │
     │  + picker  │         │  (Swift)    │
     └─────┬─────┘         └──────┬──────┘
           │                       │
           └───────────┬───────────┘
                       │
              ┌────────▼────────┐
              │ TerminalAdapter │
              │   (protocol)    │
              ├─────────────────┤
              │ Apple Terminal  │
              │ kitty           │
              │ iTerm2          │
              └─────────────────┘
```

## License

MIT
