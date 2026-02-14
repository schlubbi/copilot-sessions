import Foundation
import AppKit

/// Protocol for terminal emulator adapters
public protocol TerminalAdapter {
    /// Unique key for persistence (e.g. "terminal", "kitty", "iterm2")
    var key: String { get }

    /// Display name for this terminal
    var name: String { get }

    /// Emoji icon for this terminal
    var icon: String { get }

    /// Whether this terminal is currently available (installed + running or launchable)
    func isAvailable() -> Bool

    /// Focus a tab/window containing the given TTY device
    func focusTab(tty: String) -> Bool

    /// Launch a new tab/window running the given command
    func launch(command: [String], title: String) -> Bool
}

/// All known terminal adapters
public let allTerminalAdapters: [TerminalAdapter] = [
    AppleTerminalAdapter(),
    KittyAdapter(),
    ITermAdapter(),
]

/// Returns the user's preferred terminal, or auto-detects
public func preferredTerminalAdapter() -> TerminalAdapter {
    if let saved = UserDefaults.standard.string(forKey: "terminalAdapter"),
       let match = allTerminalAdapters.first(where: { $0.key == saved && $0.isAvailable() }) {
        return match
    }
    return detectTerminalAdapter()
}

/// Detects and returns the best available terminal adapter
public func detectTerminalAdapter() -> TerminalAdapter {
    let kitty = KittyAdapter()
    if kitty.isAvailable() { return kitty }
    return AppleTerminalAdapter()
}

// MARK: - Apple Terminal

public class AppleTerminalAdapter: TerminalAdapter {
    public let key = "terminal"
    public let name = "Terminal"
    public let icon = "🖥️"

    public func isAvailable() -> Bool {
        return true // Always present on macOS
    }

    public func focusTab(tty: String) -> Bool {
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

    public func launch(command: [String], title: String) -> Bool {
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

public class KittyAdapter: TerminalAdapter {
    public let key = "kitty"
    public let name = "kitty"
    public let icon = "🐱"
    private let kittyBin = "/Applications/kitty.app/Contents/MacOS/kitty"

    public func isAvailable() -> Bool {
        // Kitty is available if the app is installed
        return FileManager.default.fileExists(atPath: kittyBin)
    }

    /// Whether kitty remote control is active (socket exists)
    public var isRemoteControlAvailable: Bool {
        return kittySocket != nil
    }

    /// Find the kitty remote control socket (may be /tmp/kitty or /tmp/kitty-PID)
    private var kittySocket: String? {
        if FileManager.default.fileExists(atPath: "/tmp/kitty") {
            return "/tmp/kitty"
        }
        // Kitty appends PID when multiple instances or default behavior
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: "/tmp")) ?? []
        return contents
            .filter { $0.hasPrefix("kitty") }
            .sorted()
            .map { "/tmp/\($0)" }
            .first
    }

    public func focusTab(tty: String) -> Bool {
        guard let socket = kittySocket else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
            return false
        }
        guard let _ = shell([kittyBin, "@", "--to", "unix:\(socket)", "ls"]) else {
            return false
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
        return false
    }

    /// Focus by PID (more reliable for kitty than TTY)
    public func focusByPid(_ pid: Int) -> Bool {
        guard let socket = kittySocket,
              let data = shell([kittyBin, "@", "--to", "unix:\(socket)", "ls"]),
              let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
            return false
        }

        for osWindow in json {
            for tab in osWindow["tabs"] as? [[String: Any]] ?? [] {
                for window in tab["windows"] as? [[String: Any]] ?? [] {
                    for fg in window["foreground_processes"] as? [[String: Any]] ?? [] {
                        if fg["pid"] as? Int == pid {
                            let tabId = tab["id"] as? Int ?? 0
                            _ = shell([kittyBin, "@", "--to", "unix:\(socket)", "focus-tab", "--match", "id:\(tabId)"])
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    public func launch(command: [String], title: String) -> Bool {
        // Resolve command to absolute path
        let resolvedCmd = command.map { arg -> String in
            if arg == "copilot" {
                return copilotBin
            }
            return arg
        }

        if let socket = kittySocket {
            // Remote control available — open tab in existing kitty
            var cmd = [kittyBin, "@", "--to", "unix:\(socket)", "launch", "--type=tab", "--title", title]
            cmd.append(contentsOf: resolvedCmd)
            _ = shell(cmd)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
        } else {
            // No socket — launch kitty directly with the command
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: kittyBin)
            proc.arguments = ["--title", title] + resolvedCmd
            try? proc.run()
        }
        return true
    }

    /// Resolve copilot binary path
    private var copilotBin: String {
        // Use login shell to resolve PATH correctly
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "which copilot"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        return "copilot"
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

public class ITermAdapter: TerminalAdapter {
    public let key = "iterm2"
    public let name = "iTerm2"
    public let icon = "🔲"

    public func isAvailable() -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
    }

    public func focusTab(tty: String) -> Bool {
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

    public func launch(command: [String], title: String) -> Bool {
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
