import Foundation
import AppKit

/// Protocol for terminal emulator adapters
protocol TerminalAdapter {
    /// Display name for this terminal
    var name: String { get }

    /// Whether this terminal is currently available (installed + running or launchable)
    func isAvailable() -> Bool

    /// Focus a tab/window containing the given TTY device
    func focusTab(tty: String) -> Bool

    /// Launch a new tab/window running the given command
    func launch(command: [String], title: String) -> Bool
}

/// Detects and returns the best available terminal adapter
func detectTerminalAdapter() -> TerminalAdapter {
    // Prefer kitty if running with remote control
    let kitty = KittyAdapter()
    if kitty.isAvailable() { return kitty }

    // Fallback to Apple Terminal (always available on macOS)
    return AppleTerminalAdapter()
}

// MARK: - Apple Terminal

class AppleTerminalAdapter: TerminalAdapter {
    let name = "Terminal"

    func isAvailable() -> Bool {
        return true // Always present on macOS
    }

    func focusTab(tty: String) -> Bool {
        // Use AppleScript to find and focus the tab with this TTY
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScript(script) == "true"
    }

    func launch(command: [String], title: String) -> Bool {
        let cmd = command.map { $0.replacingOccurrences(of: "'", with: "'\\''") }.joined(separator: " ")
        // With accessibility permissions, use System Events to open a new tab
        // then run the command in it
        let script = """
        tell application "Terminal"
            activate
            tell application "System Events"
                tell process "Terminal"
                    click menu item "New Tab" of menu "Shell" of menu bar 1
                end tell
            end tell
            delay 0.3
            do script "\(cmd)" in selected tab of front window
        end tell
        """
        if runAppleScript(script) != nil {
            return true
        }
        // Fallback: opens a new window instead
        let fallback = """
        tell application "Terminal"
            activate
            do script "\(cmd)"
        end tell
        """
        return runAppleScript(fallback) != nil
    }

    private func runAppleScript(_ source: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
            ? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
    }
}

// MARK: - Kitty

class KittyAdapter: TerminalAdapter {
    let name = "kitty"
    private let kittyBin = "/Applications/kitty.app/Contents/MacOS/kitty"

    func isAvailable() -> Bool {
        return FileManager.default.fileExists(atPath: "/tmp/kitty")
    }

    func focusTab(tty: String) -> Bool {
        // kitty @ ls to find tab by matching foreground process TTY
        guard let data = shell([kittyBin, "@", "ls"]),
              let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else {
            return false
        }

        // Match by looking at env or foreground_processes
        // Since we can't easily get TTY from kitty, match by PID instead
        // This is called with TTY, so we need PID->TTY mapping from caller
        // For now, bring kitty to front
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
        return false
    }

    /// Focus by PID (more reliable for kitty than TTY)
    func focusByPid(_ pid: Int) -> Bool {
        guard let data = shell([kittyBin, "@", "ls"]),
              let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else {
            return false
        }

        for osWindow in json {
            for tab in osWindow["tabs"] as? [[String: Any]] ?? [] {
                for window in tab["windows"] as? [[String: Any]] ?? [] {
                    for fg in window["foreground_processes"] as? [[String: Any]] ?? [] {
                        if fg["pid"] as? Int == pid {
                            let tabId = tab["id"] as? Int ?? 0
                            _ = shell([kittyBin, "@", "focus-tab", "--match", "id:\(tabId)"])
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    func launch(command: [String], title: String) -> Bool {
        if isAvailable() {
            var cmd = [kittyBin, "@", "launch", "--type=tab", "--title", title]
            cmd.append(contentsOf: command)
            _ = shell(cmd)
        } else {
            // Kitty installed but not running — launch directly
            var cmd = [kittyBin, "--title", title]
            cmd.append(contentsOf: command)
            _ = shell(cmd)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
        return true
    }

    private func shell(_ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - iTerm2 (stub for future)

class ITermAdapter: TerminalAdapter {
    let name = "iTerm2"

    func isAvailable() -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
    }

    func focusTab(tty: String) -> Bool {
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScript(script) == "true"
    }

    func launch(command: [String], title: String) -> Bool {
        let cmd = command.map { $0.replacingOccurrences(of: "\"", with: "\\\"") }.joined(separator: " ")
        let script = """
        tell application "iTerm2"
            activate
            tell current window
                create tab with default profile
                tell current session
                    write text "\(cmd)"
                end tell
            end tell
        end tell
        """
        return runAppleScript(script) != nil
    }

    private func runAppleScript(_ source: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
            ? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
    }
}
