import Foundation

/// Exports session data to a shared JSON file for widget consumption.
/// The file at ~/Library/Application Support/CopilotSessions/widget-data.json
/// can be read by Scriptable, Shortcuts, or a future native WidgetKit extension.
public class WidgetDataExporter {
    private let filePath: String

    public init() {
        let appSupport = NSHomeDirectory() + "/Library/Application Support/CopilotSessions"
        try? FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
        filePath = appSupport + "/widget-data.json"
    }

    /// For testing: use a custom path
    public init(path: String) {
        filePath = path
    }

    /// Export session summary for widget display
    public func export(sessions: [CopilotSession]) {
        let working = sessions.filter { $0.status == .working }
        let waiting = sessions.filter { $0.status == .waiting }
        let done = sessions.filter { $0.status == .done }

        let sessionEntries = sessions.prefix(15).map { s -> [String: Any] in
            var entry: [String: Any] = [
                "id": s.id,
                "topic": s.displayLabel,
                "status": s.status.rawValue,
                "statusEmoji": s.statusEmoji,
                "terminalIcon": s.terminalType.icon,
            ]
            if !s.branch.isEmpty { entry["branch"] = s.branch }
            if !s.displayRepoName.isEmpty { entry["repository"] = s.displayRepoName }
            if !s.relativeAge.isEmpty { entry["age"] = s.relativeAge }
            if let ts = s.lastTimestamp { entry["timestamp"] = ISO8601DateFormatter().string(from: ts) }
            return entry
        }

        let data: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "counts": [
                "working": working.count,
                "waiting": waiting.count,
                "done": done.count,
                "total": sessions.count,
            ],
            "sessions": sessionEntries,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) else { return }
        FileManager.default.createFile(atPath: filePath, contents: jsonData)
    }

    /// Read exported data (for testing or widget use)
    public func read() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }
}
