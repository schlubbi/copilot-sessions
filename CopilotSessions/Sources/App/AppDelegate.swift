import AppKit
import Foundation
import CopilotSessionsLib
import Carbon.HIToolbox

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
    private let labelStore = LabelStore()
    private let widgetExporter = WidgetDataExporter()
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminal = preferredTerminalAdapter()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🤖"
        }

        // Build menu lazily on open
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Register global hotkey ⌥⇧C
        registerGlobalHotkey()

        // Load sessions in background after launch
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = self?.dataSource.loadSessions() ?? []
            DispatchQueue.main.async {
                self?.sessions = loaded
                self?.updateIcon()
            }
        }

        // Poll every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
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
        // Export data for widget consumption
        widgetExporter.export(sessions: sessions)
    }

    // MARK: - Global Hotkey (⌥⇧C)

    private func registerGlobalHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4350534D) // "CPSM"
        hotKeyID.id = 1

        // ⌥⇧C  — modifier: optionKey(0x0800) + shiftKey(0x0200), keycode 8 = 'C'
        let modifiers: UInt32 = UInt32(optionKey | shiftKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_C), modifiers, hotKeyID,
                                          GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            // Install Carbon event handler
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.statusItem.button?.performClick(nil)
                }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
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

        // Group active sessions by repository
        let activeSessions = working + waiting
        let grouped = Dictionary(grouping: activeSessions) { $0.displayRepoName.isEmpty ? "Other" : $0.displayRepoName }
        let sortedGroups = grouped.sorted { a, b in
            // Most-recently-active repo first
            let aMax = a.value.compactMap(\.lastTimestamp).max() ?? .distantPast
            let bMax = b.value.compactMap(\.lastTimestamp).max() ?? .distantPast
            return aMax > bMax
        }

        for (repoName, repoSessions) in sortedGroups {
            if sortedGroups.count > 1 || repoName != "Other" {
                let header = NSMenuItem(title: "📁 \(repoName)", action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }

            for session in repoSessions {
                let item = menuItem(for: session)
                menu.addItem(item)
            }

            menu.addItem(.separator())
        }

        // Done sessions (top 10)
        let doneSlice = Array(done.prefix(10))
        if !doneSlice.isEmpty {
            if activeSessions.isEmpty { menu.addItem(.separator()) }
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for session in doneSlice {
                let label = labelStore.label(for: session.id) ?? session.displayLabel
                let age = session.relativeAge.isEmpty ? "" : " · \(session.relativeAge)"
                let title = "⚪ \(label)\(age)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.target = self
                item.tag = tagForSession(session)
                item.toolTip = session.fullMessage.isEmpty ? session.shortId : session.fullMessage

                // Submenu for done sessions: Resume, Open PR, Set Label, Stats
                let sub = NSMenu()
                addSessionStatsItems(to: sub, session: session)
                sub.addItem(.separator())

                let resumeItem = NSMenuItem(title: "▶ Resume Session", action: #selector(handleResumeSession(_:)), keyEquivalent: "")
                resumeItem.target = self
                resumeItem.tag = tagForSession(session)
                sub.addItem(resumeItem)

                if !session.branch.isEmpty && session.branch != "main" && session.branch != "master" {
                    let prItem = NSMenuItem(title: "🔗 Open PR / Branch", action: #selector(handleOpenPR(_:)), keyEquivalent: "")
                    prItem.target = self
                    prItem.tag = tagForSession(session)
                    sub.addItem(prItem)
                }

                sub.addItem(.separator())
                let labelItem = NSMenuItem(title: "🏷️ Set Label…", action: #selector(handleSetLabel(_:)), keyEquivalent: "")
                labelItem.target = self
                labelItem.tag = tagForSession(session)
                sub.addItem(labelItem)

                item.submenu = sub
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

        // Settings submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()

        // Terminal picker
        let termHeader = NSMenuItem(title: "New sessions open in:", action: nil, keyEquivalent: "")
        termHeader.isEnabled = false
        settingsMenu.addItem(termHeader)

        let autoItem = NSMenuItem(title: "Auto-detect", action: #selector(selectTerminal(_:)), keyEquivalent: "")
        autoItem.target = self
        autoItem.tag = -1
        if UserDefaults.standard.string(forKey: "terminalAdapter") == nil {
            autoItem.state = .on
        }
        settingsMenu.addItem(autoItem)

        settingsMenu.addItem(.separator())

        for (i, adapter) in allTerminalAdapters.enumerated() {
            guard adapter.isAvailable() else { continue }
            let title = "\(adapter.icon) \(adapter.name)"
            let item = NSMenuItem(title: title, action: #selector(selectTerminal(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            if adapter.key == terminal.key,
               UserDefaults.standard.string(forKey: "terminalAdapter") != nil {
                item.state = .on
            }
            settingsMenu.addItem(item)
        }

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(doQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Build a menu item for an active session (working/waiting)
    private func menuItem(for session: CopilotSession) -> NSMenuItem {
        let label = labelStore.label(for: session.id) ?? session.displayLabel
        let branch = (session.branch.isEmpty || session.branch == "—") ? "" : "  ⌥ \(session.branch)"
        let age = session.relativeAge.isEmpty ? "" : " · \(session.relativeAge)"
        let title = "\(session.statusEmoji) \(session.terminalType.icon) \(label)\(branch)\(age)"
        let item = NSMenuItem(title: title, action: #selector(handleActiveSession(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tagForSession(session)
        item.toolTip = session.fullMessage.isEmpty ? session.shortId : session.fullMessage

        // Submenu with stats + actions
        let sub = NSMenu()
        addSessionStatsItems(to: sub, session: session)

        if !session.branch.isEmpty && session.branch != "main" && session.branch != "master" {
            sub.addItem(.separator())
            let prItem = NSMenuItem(title: "🔗 Open PR / Branch", action: #selector(handleOpenPR(_:)), keyEquivalent: "")
            prItem.target = self
            prItem.tag = tagForSession(session)
            sub.addItem(prItem)
        }

        sub.addItem(.separator())
        let labelItem = NSMenuItem(title: "🏷️ Set Label…", action: #selector(handleSetLabel(_:)), keyEquivalent: "")
        labelItem.target = self
        labelItem.tag = tagForSession(session)
        sub.addItem(labelItem)

        item.submenu = sub
        return item
    }

    /// Add session stats as disabled info items to a submenu
    private func addSessionStatsItems(to menu: NSMenu, session: CopilotSession) {
        let statusItem = NSMenuItem(title: "Status: \(session.statusLabel)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let turnsItem = NSMenuItem(title: "Turns: \(session.turns)", action: nil, keyEquivalent: "")
        turnsItem.isEnabled = false
        menu.addItem(turnsItem)

        if let ts = session.lastTimestamp {
            let age = CopilotSession.formatRelativeAge(from: ts, to: Date())
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            let dateStr = fmt.string(from: ts)
            let ageItem = NSMenuItem(title: "Last active: \(dateStr) (\(age) ago)", action: nil, keyEquivalent: "")
            ageItem.isEnabled = false
            menu.addItem(ageItem)
        }

        if !session.branch.isEmpty {
            let branchItem = NSMenuItem(title: "Branch: \(session.branch)", action: nil, keyEquivalent: "")
            branchItem.isEnabled = false
            menu.addItem(branchItem)
        }

        if !session.cwd.isEmpty && session.cwd != "/" {
            let cwdDisplay = session.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            let cwdItem = NSMenuItem(title: "CWD: \(cwdDisplay)", action: nil, keyEquivalent: "")
            cwdItem.isEnabled = false
            menu.addItem(cwdItem)
        }

        if !session.displayRepoName.isEmpty {
            let repoItem = NSMenuItem(title: "Repo: \(session.displayRepoName)", action: nil, keyEquivalent: "")
            repoItem.isEnabled = false
            menu.addItem(repoItem)
        }
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Use the session's actual terminal for focus, not the user's preferred one
            let adapter = self?.adapterForSession(session) ?? self?.terminal
            guard let adapter = adapter else { return }

            if let kitty = adapter as? KittyAdapter, let pid = session.pid, let pidInt = Int(pid) {
                _ = kitty.focusByPid(pidInt)
            } else if let tty = session.tty {
                _ = adapter.focusTab(tty: "/dev/\(tty)")
            }
        }
    }

    /// Returns the correct adapter for a session's detected terminal
    private func adapterForSession(_ session: CopilotSession) -> TerminalAdapter? {
        switch session.terminalType {
        case .terminal:  return allTerminalAdapters.first { $0.key == "terminal" }
        case .kitty:     return allTerminalAdapters.first { $0.key == "kitty" }
        case .iterm2:    return allTerminalAdapters.first { $0.key == "iterm2" }
        default:         return terminal  // fallback to preferred
        }
    }

    @objc private func handleResumeSession(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < sessions.count else { return }
        let session = sessions[sender.tag]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.terminal.launch(command: ["copilot", "--resume", session.id],
                                      title: "copilot: \(session.shortId)")
        }
    }

    @objc private func handleOpenPR(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < sessions.count else { return }
        let session = sessions[sender.tag]
        guard !session.branch.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let dir = session.cwd.isEmpty ? NSHomeDirectory() : session.cwd
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["gh", "pr", "view", session.branch, "--web"]
            proc.currentDirectoryURL = URL(fileURLWithPath: dir)
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()

            // If no PR exists, fall back to opening the branch on GitHub
            if proc.terminationStatus != 0 {
                let fallback = Process()
                fallback.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                fallback.arguments = ["gh", "browse", "--branch", session.branch]
                fallback.currentDirectoryURL = URL(fileURLWithPath: dir)
                fallback.standardOutput = FileHandle.nullDevice
                fallback.standardError = FileHandle.nullDevice
                try? fallback.run()
                fallback.waitUntilExit()
            }
        }
    }

    @objc private func handleSetLabel(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < sessions.count else { return }
        let session = sessions[sender.tag]
        let currentLabel = labelStore.label(for: session.id) ?? session.displayLabel

        let alert = NSAlert()
        alert.messageText = "Set Label"
        alert.informativeText = "Enter a custom label for this session:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = currentLabel
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newLabel = input.stringValue.trimmingCharacters(in: .whitespaces)
            labelStore.setLabel(newLabel.isEmpty ? nil : newLabel, for: session.id)
        } else if response == .alertSecondButtonReturn {
            labelStore.setLabel(nil, for: session.id)
        }
    }

    @objc private func newSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.terminal.launch(command: ["copilot"], title: "copilot: new")
        }
    }

    @objc private func selectTerminal(_ sender: NSMenuItem) {
        if sender.tag == -1 {
            // Auto-detect
            UserDefaults.standard.removeObject(forKey: "terminalAdapter")
            terminal = detectTerminalAdapter()
        } else if sender.tag >= 0, sender.tag < allTerminalAdapters.count {
            let adapter = allTerminalAdapters[sender.tag]
            UserDefaults.standard.set(adapter.key, forKey: "terminalAdapter")
            terminal = adapter
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
