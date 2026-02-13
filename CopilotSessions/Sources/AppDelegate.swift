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
    private var terminal: TerminalAdapter!
    private var timer: Timer?
    private var sessions: [CopilotSession] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminal = detectTerminalAdapter()
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

        let newItem = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(doRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let termInfo = NSMenuItem(title: "Terminal: \(terminal.name)", action: nil, keyEquivalent: "")
        termInfo.isEnabled = false
        menu.addItem(termInfo)

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

        if let tty = session.tty {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let terminal = self?.terminal else { return }
                // Try TTY-based focus first; for kitty, try PID-based
                if let kitty = terminal as? KittyAdapter, let pid = session.pid, let pidInt = Int(pid) {
                    _ = kitty.focusByPid(pidInt)
                } else {
                    _ = terminal.focusTab(tty: "/dev/\(tty)")
                }
            }
        }
    }

    @objc private func handleInactiveSession(_ sender: NSMenuItem) {
        let inactive = Array(sessions.filter { !$0.isActive }.prefix(5))
        guard sender.tag >= 0, sender.tag < inactive.count else { return }
        let session = inactive[sender.tag]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.terminal.launch(command: ["copilot", "--resume", session.id],
                                      title: "copilot: \(session.shortId)")
        }
    }

    @objc private func newSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.terminal.launch(command: ["copilot"], title: "copilot: new")
        }
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
}
