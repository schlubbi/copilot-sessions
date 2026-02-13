import Foundation

/// Represents the state of a Copilot CLI session
struct CopilotSession: Identifiable {
    let id: String           // full session UUID
    var shortId: String { String(id.prefix(12)) }
    let topic: String
    let branch: String
    let turns: Int
    let lastTimestamp: Date?
    let isActive: Bool
    let pid: String?
    let tty: String?

    var statusEmoji: String {
        isActive ? "🟢" : "⚪"
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

            let isActive = activeSids.contains(sid)
            let pid = sessionToPid[sid]
            let tty = pid.flatMap { runningPids[$0]?["tty"] }

            // Skip sessions with no data and not active
            if topic.isEmpty && !isActive { continue }

            sessions.append(CopilotSession(
                id: sid,
                topic: topic,
                branch: branch,
                turns: turns,
                lastTimestamp: lastTs,
                isActive: isActive,
                pid: pid,
                tty: tty
            ))
        }

        // Sort: active first, then by timestamp descending
        sessions.sort { a, b in
            if a.isActive != b.isActive { return a.isActive }
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
