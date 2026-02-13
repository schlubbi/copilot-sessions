import AppKit
import Foundation

// Keep delegate alive for the lifetime of the app
private var appDelegate: AppDelegate!

@main
struct CopilotSessionsApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        appDelegate = AppDelegate()
        app.delegate = appDelegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var dataSource = SessionDataSource()
    private var timer: Timer?
    private var sessions: [CopilotSession] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🤖"
        }

        // Build menu lazily on open
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Load sessions in background after launch
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = self?.dataSource.loadSessions() ?? []
            DispatchQueue.main.async {
                self?.sessions = loaded
                self?.updateIcon()
            }
        }

        // Poll every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = self?.dataSource.loadSessions() ?? []
                DispatchQueue.main.async {
                    self?.sessions = loaded
                    self?.updateIcon()
                }
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let active = sessions.filter { $0.isActive }.count
        if active > 0 {
            button.title = "🤖 \(active)"
        } else {
            button.title = "🤖"
        }
    }

    // MARK: - NSMenuDelegate — rebuild menu each time it opens

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        let active = sessions.filter { $0.isActive }
        let inactive = sessions.filter { !$0.isActive }

        if active.isEmpty && inactive.isEmpty {
            let item = NSMenuItem(title: "No sessions found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        // Active sessions
        if !active.isEmpty {
            let header = NSMenuItem(title: "Active (\(active.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for (i, session) in active.enumerated() {
                let branch = (session.branch.isEmpty || session.branch == "—") ? "" : "  ⌥ \(session.branch)"
                let title = "🟢 \(session.displayLabel)\(branch)"
                let item = NSMenuItem(title: title, action: #selector(handleSession(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i  // index into active array
                item.toolTip = "PID \(session.pid ?? "?") · \(session.turns) turns · Click to focus"
                menu.addItem(item)
            }
        }

        // Inactive sessions (top 5)
        let inactiveSlice = Array(inactive.prefix(5))
        if !inactiveSlice.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for (i, session) in inactiveSlice.enumerated() {
                let title = "⚪ \(session.displayLabel)"
                let item = NSMenuItem(title: title, action: #selector(handleInactiveSession(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i  // index into inactiveSlice
                item.toolTip = "Click to resume in new kitty tab"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(doRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(doQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func handleSession(_ sender: NSMenuItem) {
        let active = sessions.filter { $0.isActive }
        guard sender.tag >= 0, sender.tag < active.count else { return }
        let session = active[sender.tag]

        if let pid = session.pid {
            focusKittyTab(pid: pid)
        }
    }

    @objc private func handleInactiveSession(_ sender: NSMenuItem) {
        let inactive = Array(sessions.filter { !$0.isActive }.prefix(5))
        guard sender.tag >= 0, sender.tag < inactive.count else { return }
        let session = inactive[sender.tag]
        resumeInKitty(sessionId: session.id)
    }

    @objc private func doRefresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = self?.dataSource.loadSessions() ?? []
            DispatchQueue.main.async {
                self?.sessions = loaded
                self?.updateIcon()
            }
        }
    }

    @objc private func doQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Kitty integration

    private func focusKittyTab(pid: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = self.shell("/usr/bin/env", "kitty", "@", "ls"),
                  let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
                }
                return
            }

            let targetPid = Int(pid) ?? 0
            for osWindow in json {
                for tab in osWindow["tabs"] as? [[String: Any]] ?? [] {
                    for window in tab["windows"] as? [[String: Any]] ?? [] {
                        for fg in window["foreground_processes"] as? [[String: Any]] ?? [] {
                            if fg["pid"] as? Int == targetPid {
                                let tabId = tab["id"] as? Int ?? 0
                                _ = self.shell("/usr/bin/env", "kitty", "@", "focus-tab", "--match", "id:\(tabId)")
                                DispatchQueue.main.async {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
                                }
                                return
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
            }
        }
    }

    private func resumeInKitty(sessionId: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.shell("/usr/bin/env", "kitty", "@", "launch", "--type=tab",
                           "--title", "copilot: \(String(sessionId.prefix(12)))",
                           "copilot", "--resume", sessionId)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/kitty.app"))
            }
        }
    }

    private func shell(_ args: String...) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
