import Foundation
import Darwin

/// Session lifecycle status
enum SessionStatus: String {
    case working   // actively running tools or using CPU
    case waiting   // process alive, idle — waiting for user input
    case done      // no running process
}

/// Known terminal emulators with display info
enum TerminalType: String {
    case terminal = "Terminal"
    case kitty    = "kitty"
    case iterm2   = "iTerm2"
    case wezterm  = "WezTerm"
    case alacritty = "Alacritty"
    case ghostty  = "Ghostty"
    case unknown  = "?"

    var icon: String {
        switch self {
        case .terminal:  return "🖥️"
        case .kitty:     return "🐱"
        case .iterm2:    return "🔲"
        case .wezterm:   return "🌐"
        case .alacritty: return "⬛"
        case .ghostty:   return "👻"
        case .unknown:   return "💻"
        }
    }
}

/// Represents the state of a Copilot CLI session
struct CopilotSession: Identifiable {
    let id: String           // full session UUID
    var shortId: String { String(id.prefix(12)) }
    let topic: String
    let branch: String
    let turns: Int
    let lastTimestamp: Date?
    let status: SessionStatus
    let pid: String?
    let tty: String?
    let terminalType: TerminalType

    var isActive: Bool { status != .done }

    var statusEmoji: String {
        switch status {
        case .working: return "🟡"
        case .waiting: return "🟢"
        case .done:    return "⚪"
        }
    }

    var statusLabel: String {
        switch status {
        case .working: return "Working"
        case .waiting: return "Waiting for input"
        case .done:    return "Done"
        }
    }

    var displayLabel: String {
        if topic.isEmpty {
            return shortId
        }
        return topic
    }
}

/// Reads Copilot session state from disk and correlates with running processes
class SessionDataSource {
    private let sessionBase: String

    init() {
        self.sessionBase = NSHomeDirectory() + "/.copilot/session-state"
    }

    func loadSessions() -> [CopilotSession] {
        let runningPids = getRunningCopilotPids()
        let pidToSession = getPidToSession()
        let activeSids = Set(pidToSession.values)
        let sessionToPid = Dictionary(pidToSession.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        let ppidMap = ProcessInspector.buildPpidMap()

        var sessions: [CopilotSession] = []

        // Load all session snapshot data
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: sessionBase) else { return [] }

        for dir in dirs {
            let sid = dir
            let indexPath = "\(sessionBase)/\(sid)/rewind-snapshots/index.json"

            var topic = ""
            var branch = ""
            var turns = 0
            var lastTs: Date? = nil

            if let data = fm.contents(atPath: indexPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let snaps = json["snapshots"] as? [[String: Any]],
               let first = snaps.first {

                let msg = first["userMessage"] as? String ?? ""
                topic = extractTopic(from: msg)
                turns = snaps.count

                if let last = snaps.last {
                    branch = last["gitBranch"] as? String ?? ""
                    if let ts = last["timestamp"] as? String {
                        lastTs = parseISO8601(ts)
                    }
                }
            }

            let isAlive = activeSids.contains(sid)
            let pid = sessionToPid[sid]
            let tty = pid.flatMap { runningPids[$0]?["tty"] }

            let status: SessionStatus
            let termType: TerminalType
            if isAlive, let pidStr = pid, let pidInt = Int32(pidStr) {
                status = ProcessInspector.isWorking(pidInt, ppidMap: ppidMap) ? .working : .waiting
                termType = ProcessInspector.detectTerminal(pidInt)
            } else {
                status = .done
                termType = .unknown
            }

            // Skip sessions with no data and not active
            if topic.isEmpty && !isAlive { continue }

            sessions.append(CopilotSession(
                id: sid,
                topic: topic,
                branch: branch,
                turns: turns,
                lastTimestamp: lastTs,
                status: status,
                pid: pid,
                tty: tty,
                terminalType: termType
            ))
        }

        // Sort: working first, then waiting, then done, then by timestamp
        sessions.sort { a, b in
            let order: [SessionStatus: Int] = [.working: 0, .waiting: 1, .done: 2]
            let oa = order[a.status] ?? 2
            let ob = order[b.status] ?? 2
            if oa != ob { return oa < ob }
            let ta = a.lastTimestamp ?? .distantPast
            let tb = b.lastTimestamp ?? .distantPast
            return ta > tb
        }

        return sessions
    }

    // MARK: - Process discovery

    private func getRunningCopilotPids() -> [String: [String: String]] {
        guard let output = shell("/bin/ps", "-eo", "pid,tty,lstart,command") else { return [:] }
        var result: [String: [String: String]] = [:]
        for line in output.components(separatedBy: "\n") {
            if line.contains("copilot-darwin") && !line.contains("grep") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if parts.count >= 7 {
                    let pid = parts[0]
                    let tty = parts[1]
                    result[pid] = ["tty": tty]
                }
            }
        }
        return result
    }

    private func getPidToSession() -> [String: String] {
        guard let output = shell("/usr/sbin/lsof", "-c", "copilot") else { return [:] }
        var result: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            if line.contains("session-state") && line.contains("session.db") {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let pid = parts[1]
                    if let range = line.range(of: "session-state/([a-f0-9-]+)/", options: .regularExpression) {
                        let match = line[range]
                        let sid = match.replacingOccurrences(of: "session-state/", with: "")
                            .replacingOccurrences(of: "/", with: "")
                        result[pid] = sid
                    }
                }
            }
        }
        return result
    }

    // MARK: - Topic extraction

    private func extractTopic(from msg: String) -> String {
        var line = msg.components(separatedBy: "\n").first ?? ""
        // Strip URLs
        line = line.replacingOccurrences(of: "https?://\\S+\\s*,?\\s*", with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: "\\.\\.?/\\S+\\s*", with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: "^/\\S+\\s*", with: "", options: .regularExpression)

        // Strip filler prefixes
        let prefixes = [
            "I want to ", "I'd like to ", "Can you ", "Could you ", "Please ",
            "Let's ", "We need to ", "Read ", "Take a look at ", "Go through ",
            "Given ", "Looking at ", "You're a ", "At github ", "I made ",
            "I have ", "I need ", "Help me ", "Show me ", "Find ", "Identify ",
            "Research ", "Change ", "Create ", "Build ", "Write ", "Run ", "Check ",
            "and ", "the ", "that ", "this "
        ]
        for _ in 0..<3 {
            for prefix in prefixes {
                if line.lowercased().hasPrefix(prefix.lowercased()) {
                    line = String(line.dropFirst(prefix.count))
                }
            }
        }

        line = line.trimmingCharacters(in: CharacterSet(charactersIn: ",.:;?-() \t"))
        if let first = line.first {
            line = first.uppercased() + line.dropFirst()
        }
        if line.count > 35 {
            let cut = line.prefix(35)
            if let lastSpace = cut.lastIndex(of: " ") {
                line = String(cut[cut.startIndex..<lastSpace]) + "…"
            } else {
                line = String(cut) + "…"
            }
        }
        return line
    }

    // MARK: - Helpers

    private func shell(_ args: String...) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        // Read BEFORE waitUntilExit to avoid pipe buffer deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func parseISO8601(_ str: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
}

// MARK: - Native process inspection via Darwin APIs (no shell out)

enum ProcessInspector {
    /// MCP server process names — these are always-on children, not tool work
    private static let mcpNames: Set<String> = ["npm", "node", "azmcp"]

    /// Build a map of parent PID → child PIDs for all processes (takes ~1ms)
    static func buildPpidMap() -> [pid_t: [pid_t]] {
        var allPids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &allPids,
            Int32(MemoryLayout<pid_t>.stride * allPids.count))
        let count = Int(bytes) / MemoryLayout<pid_t>.stride
        var map: [pid_t: [pid_t]] = [:]
        for i in 0..<count {
            let cpid = allPids[i]
            guard cpid > 0 else { continue }
            var bsdInfo = proc_bsdinfo()
            let ret = proc_pidinfo(cpid, PROC_PIDTBSDINFO, 0, &bsdInfo,
                Int32(MemoryLayout<proc_bsdinfo>.stride))
            if ret > 0 {
                map[pid_t(bsdInfo.pbi_ppid), default: []].append(cpid)
            }
        }
        return map
    }

    /// Determines if a copilot process is actively working (running tools)
    static func isWorking(_ pid: pid_t, ppidMap: [pid_t: [pid_t]]) -> Bool {
        let children = ppidMap[pid] ?? []
        // Check if any child is a tool process (not MCP infrastructure)
        let hasToolChild = children.contains { childPid in
            guard let name = processName(childPid) else { return false }
            return !mcpNames.contains(name)
        }
        if hasToolChild { return true }

        // Fall back to CPU usage — snapshot over 50ms
        let cpu = cpuUsagePercent(pid, window: 0.05)
        return cpu > 2.0
    }

    /// Get the executable base name for a PID via proc_pidpath
    static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
        guard ret > 0 else { return nil }
        let path = String(cString: buffer)
        return (path as NSString).lastPathComponent
    }

    /// Measure CPU usage over a short window using proc_pidinfo
    static func cpuUsagePercent(_ pid: pid_t, window: TimeInterval = 0.1) -> Double {
        var info1 = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info1, size) > 0 else { return 0 }
        let t1 = info1.pti_total_user + info1.pti_total_system

        Thread.sleep(forTimeInterval: window)

        var info2 = proc_taskinfo()
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info2, size) > 0 else { return 0 }
        let t2 = info2.pti_total_user + info2.pti_total_system

        let cpuNs = Double(t2 - t1)
        let windowNs = window * 1_000_000_000.0
        return (cpuNs / windowNs) * 100.0
    }

    /// Detect which terminal emulator a copilot process is running in
    /// by walking the PPID chain via sysctl (works through root-owned login)
    static func detectTerminal(_ pid: pid_t) -> TerminalType {
        let terminalPatterns: [(String, TerminalType)] = [
            ("Terminal.app", .terminal),
            ("kitty.app", .kitty),
            ("iTerm2.app", .iterm2),
            ("WezTerm.app", .wezterm),
            ("Alacritty.app", .alacritty),
            ("Ghostty.app", .ghostty),
        ]

        var current = pid
        for _ in 0..<15 {
            if let path = processPath(current) {
                for (pattern, termType) in terminalPatterns {
                    if path.contains(pattern) { return termType }
                }
            }
            guard let ppid = parentViaSysctl(current), ppid > 0, ppid != current else { break }
            current = ppid
        }
        return .unknown
    }

    /// Full executable path for a PID
    private static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Get parent PID via sysctl (works for any process, including root-owned)
    private static func parentViaSysctl(_ pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
