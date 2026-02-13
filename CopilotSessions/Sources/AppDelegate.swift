import AppKit
import Foundation

@main
struct CopilotSessionsApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var dataSource = SessionDataSource()
    private var timer: Timer?
    private var sessions: [CopilotSession] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        refreshSessions()

        // Poll every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshSessions()
        }
    }

    private func refreshSessions() {
        sessions = dataSource.loadSessions()
        updateMenuBarIcon()
        buildMenu()
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }

        let active = sessions.filter { $0.isActive }
        let count = active.count

        // Build attributed string with colored dots
        let str = NSMutableAttributedString()

        // Copilot icon prefix
        let prefix = NSAttributedString(string: "🤖 ", attributes: [
            .font: NSFont.systemFont(ofSize: 12)
        ])
        str.append(prefix)

        if count == 0 {
            let text = NSAttributedString(string: "0", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            str.append(text)
        } else {
            // Show colored dots for each active session
            for (i, session) in active.prefix(8).enumerated() {
                let dot: String
                let color: NSColor
                if session.pid != nil {
                    dot = "●"
                    color = .systemGreen
                } else {
                    dot = "○"
                    color = .secondaryLabelColor
                }
                let dotStr = NSAttributedString(string: dot + (i < min(active.count, 8) - 1 ? " " : ""), attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: color
                ])
                str.append(dotStr)
            }
            if active.count > 8 {
                let more = NSAttributedString(string: "+\(active.count - 8)", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
                str.append(more)
            }
        }

        button.attributedTitle = str
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Active sessions section
        let active = sessions.filter { $0.isActive }
        if !active.isEmpty {
            let header = NSMenuItem(title: "Active Sessions (\(active.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for session in active {
                let title = "\(session.statusEmoji)  \(session.displayLabel)"
                let item = NSMenuItem(title: title, action: #selector(sessionClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session
                // Subtitle with branch info
                if !session.branch.isEmpty && session.branch != "—" {
                    item.toolTip = "Branch: \(session.branch) | Turns: \(session.turns) | PID: \(session.pid ?? "?")"
                }
                menu.addItem(item)
            }
        }

        // Inactive sessions section
        let inactive = sessions.filter { !$0.isActive }.prefix(5)
        if !inactive.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Recent Inactive", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for session in inactive {
                let title = "\(session.statusEmoji)  \(session.displayLabel)"
                let item = NSMenuItem(title: title, action: #selector(sessionClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session
                item.toolTip = "Click to resume in new kitty tab"
                menu.addItem(item)
            }
        }

        // Footer
        menu.addItem(.separator())

        let dashboardItem = NSMenuItem(title: "Open Dashboard in Terminal", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func sessionClicked(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? CopilotSession else { return }

        if session.isActive, let pid = session.pid {
            // Try to focus the kitty tab
            focusKittyTab(pid: pid, sessionId: session.id)
        } else {
            // Resume in new kitty tab
            resumeInKitty(sessionId: session.id)
        }
    }

    @objc private func openDashboard() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["kitty", "@", "launch", "--type=tab", "--title", "copilot-sessions",
                          "bash", "-c", "copilot-sessions --all --pick; exec bash"]
        try? proc.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
        }
    }

    @objc private func refresh() {
        refreshSessions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Kitty integration

    private func focusKittyTab(pid: String, sessionId: String) {
        // Use kitty @ ls to find the tab, then focus it
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["kitty", "@", "ls"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Fallback: just open kitty
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
            return
        }

        let targetPid = Int(pid) ?? 0
        for osWindow in json {
            for tab in osWindow["tabs"] as? [[String: Any]] ?? [] {
                for window in tab["windows"] as? [[String: Any]] ?? [] {
                    let fgProcs = window["foreground_processes"] as? [[String: Any]] ?? []
                    for fg in fgProcs {
                        if fg["pid"] as? Int == targetPid {
                            let tabId = tab["id"] as? Int ?? 0
                            let focusProc = Process()
                            focusProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                            focusProc.arguments = ["kitty", "@", "focus-tab", "--match", "id:\(tabId)"]
                            try? focusProc.run()
                            focusProc.waitUntilExit()
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
                            return
                        }
                    }
                }
            }
        }

        // Not found in kitty — just bring kitty to front
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
    }

    private func resumeInKitty(sessionId: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["kitty", "@", "launch", "--type=tab",
                          "--title", "copilot: \(String(sessionId.prefix(12)))",
                          "copilot", "--resume", sessionId]
        try? proc.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
        }
    }
}
