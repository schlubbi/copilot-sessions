# copilot-sessions

A session dashboard and manager for [GitHub Copilot CLI](https://github.com/github/copilot-cli), with [kitty](https://sw.kovidgoyal.net/kitty/) terminal integration.

Inspired by [nice-semaphore](https://github.com/nice-computer/nice-semaphore) for Claude Code.

## Features

- **CLI dashboard** — see all active and recent Copilot sessions at a glance
- **Interactive picker** — select a session to focus its tab or resume it
- **Kitty integration** — auto-focus the correct terminal tab, or open a new one
- **macOS menu bar app** — always-visible session status with click-to-focus

## Requirements

- macOS 13+
- [GitHub Copilot CLI](https://github.com/github/copilot-cli)
- [kitty terminal](https://sw.kovidgoyal.net/kitty/) with remote control enabled
- Python 3.9+
- Swift 5.9+ (for menu bar app)

## Kitty Setup

Add to `~/.config/kitty/kitty.conf`:

```
allow_remote_control yes
listen_on unix:/tmp/kitty
```

## Install

```bash
make install
```

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

# Resume an inactive session in a new kitty tab
copilot-sessions --resume <session-id>
```

### Menu Bar App

```bash
# Build and run
make run-menubar

# Or run directly
./CopilotSessions/.build/release/CopilotSessions
```

The menu bar shows 🤖 with green dots for each active session. Click to see the full list — click a session to focus or resume it.

## How It Works

The tool reads from three data sources:

1. **`ps`** — finds running `copilot-darwin` processes (PID, TTY, start time)
2. **`lsof`** — maps PIDs to session IDs via open `session.db` files
3. **`~/.copilot/session-state/*/rewind-snapshots/index.json`** — session metadata (first message, branch, turn count)

Kitty integration uses `kitty @` remote control to list windows, match by PID, and focus or launch tabs.
