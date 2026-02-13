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
        let working = sessions.filter { $0.status == .working }.count
        if working > 0 {
            button.title = "🤖⚡\(active)"
        } else if active > 0 {
            button.title = "🤖 \(active)"
        } else {
            button.title = "🤖"
        }
    }

    // MARK: - NSMenuDelegate — rebuild menu each time it opens

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        let working = sessions.filter { $0.status == .working }
        let waiting = sessions.filter { $0.status == .waiting }
        let done = sessions.filter { $0.status == .done }

        if working.isEmpty && waiting.isEmpty && done.isEmpty {
            let item = NSMenuItem(title: "No sessions found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        // Working sessions
        if !working.isEmpty {
            let header = NSMenuItem(title: "Working (\(working.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for session in working {
                let branch = (session.branch.isEmpty || session.branch == "—") ? "" : "  ⌥ \(session.branch)"
                let title = "🟡 \(session.terminalType.icon) \(session.displayLabel)\(branch)"
                let item = NSMenuItem(title: title, action: #selector(handleActiveSession(_:)), keyEquivalent: "")
                item.target = self
                item.tag = tagForSession(session)
                item.toolTip = "PID \(session.pid ?? "?") · \(session.turns) turns · Working · \(session.terminalType.rawValue)"
                menu.addItem(item)
            }
        }

        // Waiting sessions
        if !waiting.isEmpty {
            if !working.isEmpty { menu.addItem(.separator()) }
            let header = NSMenuItem(title: "Waiting for input (\(waiting.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for session in waiting {
                let branch = (session.branch.isEmpty || session.branch == "—") ? "" : "  ⌥ \(session.branch)"
                let title = "🟢 \(session.terminalType.icon) \(session.displayLabel)\(branch)"
                let item = NSMenuItem(title: title, action: #selector(handleActiveSession(_:)), keyEquivalent: "")
                item.target = self
                item.tag = tagForSession(session)
                item.toolTip = "PID \(session.pid ?? "?") · \(session.turns) turns · Waiting for input · \(session.terminalType.rawValue)"
                menu.addItem(item)
            }
        }

        // Done sessions (top 5)
        let doneSlice = Array(done.prefix(5))
        if !doneSlice.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for session in doneSlice {
                let title = "⚪ \(session.displayLabel)"
                let item = NSMenuItem(title: title, action: #selector(handleDoneSession(_:)), keyEquivalent: "")
                item.target = self
                item.tag = tagForSession(session)
                item.toolTip = "Click to resume in new tab"
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

    /// Map session to a stable tag index in the sessions array
    private func tagForSession(_ session: CopilotSession) -> Int {
        return sessions.firstIndex(where: { $0.id == session.id }) ?? -1
    }

    // MARK: - Actions

    @objc private func handleActiveSession(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < sessions.count else { return }
        let session = sessions[sender.tag]
        guard session.isActive else { return }

        if let tty = session.tty {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let terminal = self?.terminal else { return }
                if let kitty = terminal as? KittyAdapter, let pid = session.pid, let pidInt = Int(pid) {
                    _ = kitty.focusByPid(pidInt)
                } else {
                    _ = terminal.focusTab(tty: "/dev/\(tty)")
                }
            }
        }
    }

    @objc private func handleDoneSession(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < sessions.count else { return }
        let session = sessions[sender.tag]
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
