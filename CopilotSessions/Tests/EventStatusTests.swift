import XCTest
@testable import CopilotSessionsLib

final class EventStatusTests: XCTestCase {
    var tmpDir: String!
    var ds: SessionDataSource!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "copilot-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        ds = SessionDataSource()
        // Point sessionBase at our temp dir
        ds.sessionBase = tmpDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    func testTurnEndMeansWaiting() {
        let sid = "test-session"
        createEventsFile(sid: sid, lastEvent: "assistant.turn_end")
        XCTAssertEqual(ds.lastEventStatus(sessionId: sid), .waiting)
    }

    func testTurnStartMeansWorking() {
        let sid = "test-session"
        createEventsFile(sid: sid, lastEvent: "assistant.turn_start")
        XCTAssertEqual(ds.lastEventStatus(sessionId: sid), .working)
    }

    func testToolExecutionStartMeansWorking() {
        let sid = "test-session"
        createEventsFile(sid: sid, lastEvent: "tool.execution_start")
        XCTAssertEqual(ds.lastEventStatus(sessionId: sid), .working)
    }

    func testUserMessageMeansWorking() {
        let sid = "test-session"
        createEventsFile(sid: sid, lastEvent: "user.message")
        XCTAssertEqual(ds.lastEventStatus(sessionId: sid), .working)
    }

    func testAssistantMessageMeansWorking() {
        let sid = "test-session"
        createEventsFile(sid: sid, lastEvent: "assistant.message")
        XCTAssertEqual(ds.lastEventStatus(sessionId: sid), .working)
    }

    func testNoEventsFileReturnsNil() {
        XCTAssertNil(ds.lastEventStatus(sessionId: "nonexistent"))
    }

    func testEmptyEventsFileReturnsNil() {
        let sid = "test-session"
        let dir = "\(tmpDir!)/\(sid)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(dir)/events.jsonl", contents: Data())
        XCTAssertNil(ds.lastEventStatus(sessionId: sid))
    }

    // MARK: - Helpers

    private func createEventsFile(sid: String, lastEvent: String) {
        let dir = "\(tmpDir!)/\(sid)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let events = [
            "{\"type\":\"session.start\",\"timestamp\":\"2026-02-14T21:00:00Z\",\"data\":{}}",
            "{\"type\":\"user.message\",\"timestamp\":\"2026-02-14T21:01:00Z\",\"data\":{\"content\":\"test\"}}",
            "{\"type\":\"\(lastEvent)\",\"timestamp\":\"2026-02-14T21:02:00Z\",\"data\":{}}"
        ].joined(separator: "\n") + "\n"
        try! events.write(toFile: "\(dir)/events.jsonl", atomically: true, encoding: .utf8)
    }
}
