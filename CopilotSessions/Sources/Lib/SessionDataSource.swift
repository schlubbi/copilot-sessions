import Foundation
import Darwin

/// Session lifecycle status
public enum SessionStatus: String {
    case working   // actively running tools or using CPU
    case waiting   // process alive, idle — waiting for user input
    case done      // no running process
}

/// Known terminal emulators with display info
public enum TerminalType: String {
    case terminal = "Terminal"
    case kitty    = "kitty"
    case iterm2   = "iTerm2"
    case wezterm  = "WezTerm"
    case alacritty = "Alacritty"
    case ghostty  = "Ghostty"
    case unknown  = "?"

    public var icon: String {
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
public struct CopilotSession: Identifiable {
    public let id: String
    public var shortId: String { String(id.prefix(12)) }
    public let topic: String
    public let fullMessage: String
    public let branch: String
    public let turns: Int
    public let lastTimestamp: Date?
    public let status: SessionStatus
    public let pid: String?
    public let tty: String?
    public let terminalType: TerminalType
    public let repository: String  // e.g. "github/github" or ""
    public let cwd: String         // working directory

    public var isActive: Bool { status != .done }

    public var statusEmoji: String {
        switch status {
        case .working: return "🟡"
        case .waiting: return "🟢"
        case .done:    return "⚪"
        }
    }

    public var statusLabel: String {
        switch status {
        case .working: return "Working"
        case .waiting: return "Waiting for input"
        case .done:    return "Done"
        }
    }

    public var displayLabel: String {
        if topic.isEmpty {
            return shortId
        }
        return topic
    }

    /// Human-readable relative age (e.g. "5m", "3h", "2d")
    public var relativeAge: String {
        guard let ts = lastTimestamp else { return "" }
        return CopilotSession.formatRelativeAge(from: ts, to: Date())
    }

    /// Format a relative age string between two dates
    public static func formatRelativeAge(from: Date, to: Date) -> String {
        let seconds = Int(to.timeIntervalSince(from))
        if seconds < 0 { return "" }
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        let months = days / 30
        return "\(months)mo"
    }

    /// Short display name for the repository (last 2 path components or folder name)
    public var displayRepoName: String {
        if !repository.isEmpty { return repository }
        if cwd.isEmpty || cwd == "/" { return "" }
        let parts = cwd.components(separatedBy: "/").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[parts.count - 2])/\(parts.last!)"
        }
        return parts.last ?? ""
    }

    public init(id: String, topic: String, fullMessage: String, branch: String,
                turns: Int, lastTimestamp: Date?, status: SessionStatus,
                pid: String?, tty: String?, terminalType: TerminalType,
                repository: String = "", cwd: String = "") {
        self.id = id; self.topic = topic; self.fullMessage = fullMessage
        self.branch = branch; self.turns = turns; self.lastTimestamp = lastTimestamp
        self.status = status; self.pid = pid; self.tty = tty; self.terminalType = terminalType
        self.repository = repository; self.cwd = cwd
    }
}

/// Reads Copilot session state from disk and correlates with running processes
public class SessionDataSource {
    public var sessionBase: String

    public init() {
        self.sessionBase = NSHomeDirectory() + "/.copilot/session-state"
    }

    public func loadSessions() -> [CopilotSession] {
        let runningPids = getRunningCopilotPids()
        let pidToSession = getPidToSession()
        let activeSids = Set(pidToSession.values)
        let sessionToPid = Dictionary(pidToSession.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        let copilotPidSet = Set(pidToSession.keys.compactMap { Int32($0) })
        let ppidMap = ProcessInspector.buildPpidMap(forPids: copilotPidSet)

        var sessions: [CopilotSession] = []

        // Load all session snapshot data
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: sessionBase) else { return [] }

        for dir in dirs {
            let sid = dir
            let indexPath = "\(sessionBase)/\(sid)/rewind-snapshots/index.json"

            var topic = ""
            var fullMsg = ""
            var branch = ""
            var turns = 0
            var lastTs: Date? = nil
            var repository = ""
            var cwd = ""

            // Always parse workspace.yaml for repo/cwd/branch metadata
            let yamlPath = "\(sessionBase)/\(sid)/workspace.yaml"
            if let yamlStr = try? String(contentsOfFile: yamlPath, encoding: .utf8) {
                for line in yamlStr.components(separatedBy: "\n") {
                    if line.hasPrefix("repository: ") {
                        repository = String(line.dropFirst("repository: ".count)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("cwd: ") {
                        cwd = String(line.dropFirst("cwd: ".count)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("branch: ") && branch.isEmpty {
                        branch = String(line.dropFirst("branch: ".count)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("summary: ") {
                        let val = String(line.dropFirst("summary: ".count)).trimmingCharacters(in: .whitespaces)
                        if !val.isEmpty && val != "''" {
                            topic = val
                        }
                    } else if line.hasPrefix("updated_at: ") {
                        let val = String(line.dropFirst("updated_at: ".count)).trimmingCharacters(in: .whitespaces)
                        lastTs = parseISO8601(val)
                    }
                }
            }

            if let data = fm.contents(atPath: indexPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let snaps = json["snapshots"] as? [[String: Any]],
               let first = snaps.first {

                let msg = first["userMessage"] as? String ?? ""
                fullMsg = msg
                // Only use first user message as topic if workspace.yaml summary is empty
                if topic.isEmpty { topic = extractTopic(from: msg) }
                turns = snaps.count

                if let last = snaps.last {
                    if branch.isEmpty { branch = last["gitBranch"] as? String ?? "" }
                    if let ts = last["timestamp"] as? String {
                        lastTs = parseISO8601(ts)
                    }
                }
            } else {
                // Fallback for sessions without rewind-snapshots: parse events.jsonl
                let eventsPath = "\(sessionBase)/\(sid)/events.jsonl"
                if let eventsData = try? String(contentsOfFile: eventsPath, encoding: .utf8) {
                    var userMsgCount = 0
                    for line in eventsData.components(separatedBy: "\n") where !line.isEmpty {
                        guard let lineData = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = obj["type"] as? String else { continue }
                        if type == "user.message" {
                            userMsgCount += 1
                            if userMsgCount == 1, let data = obj["data"] as? [String: Any] {
                                let msg = data["content"] as? String ?? ""
                                fullMsg = msg
                                if topic.isEmpty { topic = extractTopic(from: msg) }
                            }
                        }
                    }
                    turns = max(turns, userMsgCount)
                }
            }

            let isAlive = activeSids.contains(sid)
            let pid = sessionToPid[sid]
            let tty = pid.flatMap { runningPids[$0]?["tty"] }

            let status: SessionStatus
            let termType: TerminalType
            if isAlive, let pidStr = pid, let pidInt = Int32(pidStr) {
                // Primary: derive status from events.jsonl (ground truth)
                // Fallback: process heuristic (child process inspection)
                status = lastEventStatus(sessionId: sid)
                    ?? (ProcessInspector.isWorking(pidInt, ppidMap: ppidMap) ? .working : .waiting)
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
                fullMessage: fullMsg,
                branch: branch,
                turns: turns,
                lastTimestamp: lastTs,
                status: status,
                pid: pid,
                tty: tty,
                terminalType: termType,
                repository: repository,
                cwd: cwd
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

    func extractTopic(from msg: String) -> String {
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

    /// Determine session status from the last event in events.jsonl.
    /// Returns .working if the assistant/tool is mid-turn, .waiting if the
    /// last turn ended (awaiting user input), or nil if no events file.
    func lastEventStatus(sessionId sid: String) -> SessionStatus? {
        let eventsPath = "\(sessionBase)/\(sid)/events.jsonl"
        guard let fh = FileHandle(forReadingAtPath: eventsPath) else { return nil }
        defer { fh.closeFile() }

        // Read the last ~4KB to find the final event (avoids reading multi-MB files)
        let fileSize = fh.seekToEndOfFile()
        let readStart = fileSize > 4096 ? fileSize - 4096 : 0
        fh.seek(toFileOffset: readStart)
        let tailData = fh.readDataToEndOfFile()
        guard let tail = String(data: tailData, encoding: .utf8) else { return nil }

        var lastType: String?
        for line in tail.components(separatedBy: "\n").reversed() where !line.isEmpty {
            guard let ld = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            lastType = type
            break
        }

        guard let eventType = lastType else { return nil }
        // Session is idle when the assistant finished its turn
        if eventType == "assistant.turn_end" { return .waiting }
        // Actively processing
        return .working
    }

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

    func parseISO8601(_ str: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
}

// MARK: - Native process inspection via Darwin APIs (no shell out)

public enum ProcessInspector {
    /// MCP server process names — these are always-on children, not tool work
    static let mcpNames: Set<String> = ["npm", "node", "azmcp"]

    /// Build a map of parent PID → child PIDs, scoped to the given PIDs and their descendants.
    /// Only inspects the provided PIDs to avoid triggering macOS TCC prompts for unrelated apps.
    public static func buildPpidMap(forPids pids: Set<pid_t> = []) -> [pid_t: [pid_t]] {
        var allPids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &allPids,
            Int32(MemoryLayout<pid_t>.stride * allPids.count))
        let count = Int(bytes) / MemoryLayout<pid_t>.stride

        // First pass: build full PPID lookup (pid → parent) using only the lightweight pbi_ppid
        var pidToParent: [pid_t: pid_t] = [:]
        for i in 0..<count {
            let cpid = allPids[i]
            guard cpid > 0 else { continue }
            var bsdInfo = proc_bsdinfo()
            let ret = proc_pidinfo(cpid, PROC_PIDTBSDINFO, 0, &bsdInfo,
                Int32(MemoryLayout<proc_bsdinfo>.stride))
            if ret > 0 {
                pidToParent[cpid] = pid_t(bsdInfo.pbi_ppid)
            }
        }

        // If no scope provided, return full map (for tests/backward compat)
        if pids.isEmpty {
            var map: [pid_t: [pid_t]] = [:]
            for (child, parent) in pidToParent {
                map[parent, default: []].append(child)
            }
            return map
        }

        // Second pass: collect only PIDs relevant to the scoped set (children + ancestors)
        var relevant = pids
        // Add all descendants
        var queue = Array(pids)
        while !queue.isEmpty {
            let p = queue.removeFirst()
            for (child, parent) in pidToParent where parent == p && !relevant.contains(child) {
                relevant.insert(child)
                queue.append(child)
            }
        }

        var map: [pid_t: [pid_t]] = [:]
        for child in relevant {
            if let parent = pidToParent[child] {
                map[parent, default: []].append(child)
            }
        }
        return map
    }

    /// Determines if a copilot process is actively working (running tools)
    public static func isWorking(_ pid: pid_t, ppidMap: [pid_t: [pid_t]]) -> Bool {
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
    public static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
        guard ret > 0 else { return nil }
        let path = String(cString: buffer)
        return (path as NSString).lastPathComponent
    }

    /// Measure CPU usage over a short window using proc_pidinfo
    public static func cpuUsagePercent(_ pid: pid_t, window: TimeInterval = 0.1) -> Double {
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
    public static func detectTerminal(_ pid: pid_t) -> TerminalType {
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
