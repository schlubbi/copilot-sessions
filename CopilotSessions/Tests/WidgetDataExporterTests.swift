import XCTest
@testable import CopilotSessionsLib

final class WidgetDataExporterTests: XCTestCase {
    var tmpFile: String!
    var exporter: WidgetDataExporter!

    override func setUp() {
        super.setUp()
        tmpFile = NSTemporaryDirectory() + "widget-test-\(UUID().uuidString).json"
        exporter = WidgetDataExporter(path: tmpFile)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpFile)
        super.tearDown()
    }

    func testExportCreatesFile() {
        exporter.export(sessions: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpFile))
    }

    func testExportEmptySessions() {
        exporter.export(sessions: [])
        let data = exporter.read()
        XCTAssertNotNil(data)
        let counts = data?["counts"] as? [String: Int]
        XCTAssertEqual(counts?["working"], 0)
        XCTAssertEqual(counts?["waiting"], 0)
        XCTAssertEqual(counts?["done"], 0)
        XCTAssertEqual(counts?["total"], 0)
        let sessions = data?["sessions"] as? [[String: Any]]
        XCTAssertEqual(sessions?.count, 0)
    }

    func testExportWithSessions() {
        let sessions = [
            makeSession(topic: "Fix bug", status: .working, branch: "fix/bug"),
            makeSession(topic: "Review PR", status: .waiting, repository: "github/github"),
            makeSession(topic: "Old task", status: .done),
        ]

        exporter.export(sessions: sessions)
        let data = exporter.read()
        XCTAssertNotNil(data)

        let counts = data?["counts"] as? [String: Int]
        XCTAssertEqual(counts?["working"], 1)
        XCTAssertEqual(counts?["waiting"], 1)
        XCTAssertEqual(counts?["done"], 1)
        XCTAssertEqual(counts?["total"], 3)

        let exported = data?["sessions"] as? [[String: Any]]
        XCTAssertEqual(exported?.count, 3)
        XCTAssertEqual(exported?[0]["topic"] as? String, "Fix bug")
        XCTAssertEqual(exported?[0]["status"] as? String, "working")
        XCTAssertEqual(exported?[0]["statusEmoji"] as? String, "🟡")
        XCTAssertEqual(exported?[0]["branch"] as? String, "fix/bug")
        XCTAssertEqual(exported?[1]["repository"] as? String, "github/github")
    }

    func testExportIncludesTimestamp() {
        exporter.export(sessions: [])
        let data = exporter.read()
        XCTAssertNotNil(data?["updatedAt"] as? String)
    }

    func testExportLimitsTo15Sessions() {
        let sessions = (0..<20).map { i in
            makeSession(topic: "Session \(i)", status: .done)
        }
        exporter.export(sessions: sessions)
        let data = exporter.read()
        let exported = data?["sessions"] as? [[String: Any]]
        XCTAssertEqual(exported?.count, 15)
    }

    func testExportOverwritesPreviousData() {
        exporter.export(sessions: [makeSession(topic: "First", status: .working)])
        exporter.export(sessions: [])
        let data = exporter.read()
        let sessions = data?["sessions"] as? [[String: Any]]
        XCTAssertEqual(sessions?.count, 0)
    }

    func testReadBeforeExportReturnsNil() {
        let fresh = WidgetDataExporter(path: "/tmp/nonexistent-\(UUID().uuidString).json")
        XCTAssertNil(fresh.read())
    }

    private func makeSession(
        topic: String,
        status: SessionStatus,
        branch: String = "",
        repository: String = ""
    ) -> CopilotSession {
        CopilotSession(
            id: UUID().uuidString, topic: topic, fullMessage: topic, branch: branch,
            turns: 5, lastTimestamp: Date(), status: status,
            pid: nil, tty: nil, terminalType: .terminal,
            repository: repository, cwd: ""
        )
    }
}
