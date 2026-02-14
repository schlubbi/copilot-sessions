import XCTest
@testable import CopilotSessionsLib

final class TopicPriorityTests: XCTestCase {
    var tmpDir: String!
    var ds: SessionDataSource!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "copilot-topic-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        ds = SessionDataSource()
        ds.sessionBase = tmpDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    // MARK: - workspace.yaml summary takes priority

    func testSummaryPreferredOverFirstMessage() {
        let sid = "priority-test"
        createSessionWithBoth(sid: sid, summary: "Track Copilot Sessions", firstMessage: "I want to keep track of my copilot sessions")
        let topic = loadTopic(sid: sid)
        XCTAssertEqual(topic, "Track Copilot Sessions")
    }

    func testFirstMessageUsedWhenNoSummary() {
        let sid = "no-summary-test"
        createSessionWithBoth(sid: sid, summary: nil, firstMessage: "Fix the build pipeline")
        let topic = loadTopic(sid: sid)
        XCTAssertEqual(topic, "Fix the build pipeline")
    }

    func testEmptySummaryFallsBackToMessage() {
        let sid = "empty-summary-test"
        createSessionWithBoth(sid: sid, summary: "", firstMessage: "Add new endpoint for users")
        let topic = loadTopic(sid: sid)
        XCTAssertEqual(topic, "Add new endpoint for users")
    }

    func testSummaryPreferredOverEventsJsonl() {
        let sid = "summary-vs-events"
        let dir = "\(tmpDir!)/\(sid)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let yaml = "id: \(sid)\nsummary: Analyze MySQL Incident Trends\ncwd: /tmp\n"
        try! yaml.write(toFile: "\(dir)/workspace.yaml", atomically: true, encoding: .utf8)
        let events = [
            "{\"type\":\"user.message\",\"timestamp\":\"2026-02-14T21:01:00Z\",\"data\":{\"content\":\"I want to look at mysql issues\"}}",
        ].joined(separator: "\n") + "\n"
        try! events.write(toFile: "\(dir)/events.jsonl", atomically: true, encoding: .utf8)
        let topic = loadTopic(sid: sid)
        XCTAssertEqual(topic, "Analyze MySQL Incident Trends")
    }

    func testEventsJsonlUsedWhenNoSummary() {
        let sid = "events-only"
        let dir = "\(tmpDir!)/\(sid)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let yaml = "id: \(sid)\ncwd: /tmp\n"
        try! yaml.write(toFile: "\(dir)/workspace.yaml", atomically: true, encoding: .utf8)
        let events = [
            "{\"type\":\"user.message\",\"timestamp\":\"2026-02-14T21:01:00Z\",\"data\":{\"content\":\"Deploy the new service\"}}",
        ].joined(separator: "\n") + "\n"
        try! events.write(toFile: "\(dir)/events.jsonl", atomically: true, encoding: .utf8)
        let topic = loadTopic(sid: sid)
        XCTAssertEqual(topic, "Deploy the new service")
    }

    func testSummaryOnlySessionWorks() {
        let sid = "summary-only"
        let dir = "\(tmpDir!)/\(sid)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let yaml = "id: \(sid)\nsummary: Design Widget Layout\ncwd: /tmp\n"
        try! yaml.write(toFile: "\(dir)/workspace.yaml", atomically: true, encoding: .utf8)
        let topic = loadTopic(sid: sid)
        XCTAssertEqual(topic, "Design Widget Layout")
    }

    // MARK: - Helpers

    /// Create a session with both workspace.yaml (optional summary) and rewind-snapshots
    private func createSessionWithBoth(sid: String, summary: String?, firstMessage: String) {
        let dir = "\(tmpDir!)/\(sid)"
        let snapDir = "\(dir)/rewind-snapshots"
        try! FileManager.default.createDirectory(atPath: snapDir, withIntermediateDirectories: true)

        var yaml = "id: \(sid)\ncwd: /tmp\n"
        if let s = summary, !s.isEmpty { yaml += "summary: \(s)\n" }
        try! yaml.write(toFile: "\(dir)/workspace.yaml", atomically: true, encoding: .utf8)

        let index: [String: Any] = [
            "version": 1,
            "snapshots": [
                ["snapshotId": "snap1", "userMessage": firstMessage, "timestamp": "2026-02-14T21:00:00Z", "gitBranch": "main"]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: index)
        try! data.write(to: URL(fileURLWithPath: "\(snapDir)/index.json"))
    }

    /// Load sessions and return the topic for the given session ID (inactive sessions need a topic to appear)
    private func loadTopic(sid: String) -> String? {
        let sessions = ds.loadSessions()
        return sessions.first(where: { $0.id == sid })?.topic
    }
}
