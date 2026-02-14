import Foundation

/// Persists user-defined labels for sessions
public class LabelStore {
    private var labels: [String: String] = [:]
    private let filePath: String

    public init() {
        let appSupport = NSHomeDirectory() + "/Library/Application Support/CopilotSessions"
        try? FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
        filePath = appSupport + "/labels.json"
        load()
    }

    /// For testing: use a custom path
    public init(path: String) {
        filePath = path
        load()
    }

    /// Get the custom label for a session, or nil if not set
    public func label(for sessionId: String) -> String? {
        return labels[sessionId]
    }

    /// Set or clear a custom label for a session
    public func setLabel(_ label: String?, for sessionId: String) {
        if let label = label, !label.isEmpty {
            labels[sessionId] = label
        } else {
            labels.removeValue(forKey: sessionId)
        }
        save()
    }

    /// All session IDs with labels
    public var allLabeledSessionIds: Set<String> {
        Set(labels.keys)
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        labels = dict
    }

    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: labels, options: [.prettyPrinted, .sortedKeys]) else { return }
        FileManager.default.createFile(atPath: filePath, contents: data)
    }
}
