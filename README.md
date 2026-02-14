# copilot-sessions

A session dashboard and manager for [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli). See all your sessions at a glance, focus the right terminal tab, or resume old sessions — from the command line or a macOS menu bar app.

Inspired by [nice-semaphore](https://github.com/nice-computer/nice-semaphore) for Claude Code.

## Features

### Menu Bar App
- **🤖 Status icon** — shows active session count, ⚡ when sessions are working
- **Session status** — 🟡 working, 🟢 waiting for input, ⚪ done (derived from `events.jsonl`)
- **Group by repository** — sessions organized under repo headers (📁 github/github)
- **Terminal detection** — 🖥️ Terminal, 🐱 kitty, 🔲 iTerm2, 👻 Ghostty, 🌐 WezTerm, ⬛ Alacritty
- **Session age** — relative timestamps (5m, 3h, 2d) inline
- **Click to focus** — jumps to the session's terminal tab
- **Resume sessions** — reopen done sessions with `copilot --resume`
- **Open PR / Branch** — opens the session's branch on GitHub via `gh`
- **Session stats** — submenu with turns, duration, branch, CWD, repo
- **Custom labels** — rename sessions with persistent labels (🏷️)
- **Global hotkey** — `⌥⇧C` opens the menu from anywhere
- **Settings** — pick preferred terminal for new sessions
- **Widget data export** — writes JSON for Scriptable/Shortcuts desktop widgets

### CLI Dashboard
- **Table view** — all active and recent sessions with topic, branch, turns
- **Interactive picker** — select a session to focus or resume

## Requirements

- macOS 13+
- [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
- Python 3.9+ (for CLI)
- Swift 5.9+ (for menu bar app)

## Install

```bash
git clone https://github.com/schlubbi/copilot-sessions.git
cd copilot-sessions
make install
```

This symlinks the CLI to `~/.local/bin/copilot-sessions` and builds the menu bar app with ad-hoc code signing.

To make the menu bar app findable via Spotlight:

```bash
ln -sf $(pwd)/CopilotSessions.app ~/Applications/CopilotSessions.app
```

To auto-start on login, add `CopilotSessions.app` in **System Settings → General → Login Items**.

## Usage

### Menu Bar App

```bash
make run-menubar
# or
open CopilotSessions.app
```

The menu bar shows 🤖 with active session count. Click to see all sessions grouped by repository. Each session has a submenu with stats and actions (Resume, Open PR, Set Label).

**Keyboard shortcut:** Press `⌥⇧C` from anywhere to open the menu.

### CLI

```bash
copilot-sessions            # Dashboard of active sessions
copilot-sessions --all      # Include recent inactive sessions
copilot-sessions --pick     # Interactive picker
copilot-sessions --focus ID # Focus a session's tab
copilot-sessions --resume ID # Resume in new terminal tab
```

### Desktop Widget (Scriptable)

The app exports session data to `~/Library/Application Support/CopilotSessions/widget-data.json` every 5 seconds.

1. Install [Scriptable](https://scriptable.app) from the Mac App Store
2. Create a new script and paste `widgets/CopilotSessions.scriptable.js`
3. Add a Scriptable widget to your desktop and select the script

## Terminal Support

| Terminal | Focus | New Tab | Detection |
|----------|-------|---------|-----------|
| **Apple Terminal** | ✅ AppleScript | ✅ System Events | Always available |
| **kitty** | ✅ Remote control | ✅ `kitty @` | `allow_remote_control yes` |
| **iTerm2** | ✅ AppleScript | ✅ AppleScript | Auto-detected |

### kitty Setup

Add to `~/.config/kitty/kitty.conf`:

```
allow_remote_control yes
listen_on unix:/tmp/kitty
```

### Adding a New Terminal

Implement `TerminalAdapter` in `CopilotSessions/Sources/Lib/TerminalAdapter.swift` and add it to `allTerminalAdapters`.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Data Sources                    │
│                                                  │
│  ps ─────────► running copilot PIDs + TTYs       │
│  lsof ───────► PID → session ID mapping          │
│  workspace.yaml ► repo, branch, summary, cwd     │
│  events.jsonl ► session status (ground truth)     │
│  rewind-snapshots ► topic, turns, timestamps      │
└──────────────────────┬──────────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
     ┌─────▼─────┐         ┌──────▼──────┐
     │    CLI     │         │  Menu Bar   │──► widget-data.json
     │ dashboard  │         │    App      │──► LabelStore
     │  + picker  │         │  (Swift)    │──► Global Hotkey
     └─────┬─────┘         └──────┬──────┘
           │                       │
           └───────────┬───────────┘
                       │
              ┌────────▼────────┐
              │ TerminalAdapter │
              ├─────────────────┤
              │ Apple Terminal  │
              │ kitty           │
              │ iTerm2          │
              └─────────────────┘
```

## Testing

```bash
cd CopilotSessions
swift test
```

88 tests covering: topic extraction, session model, process inspection, terminal adapters, event status detection, relative age formatting, repository grouping, label persistence, widget data export.

## License

MIT
