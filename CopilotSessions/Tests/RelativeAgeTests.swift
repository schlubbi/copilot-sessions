import XCTest
@testable import CopilotSessionsLib

final class RelativeAgeTests: XCTestCase {
    func testJustNow() {
        let now = Date()
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now, to: now), "now")
    }

    func testSecondsShowAsNow() {
        let now = Date()
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-30), to: now), "now")
    }

    func testMinutes() {
        let now = Date()
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-120), to: now), "2m")
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-3540), to: now), "59m")
    }

    func testHours() {
        let now = Date()
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-3600), to: now), "1h")
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-7200), to: now), "2h")
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-82800), to: now), "23h")
    }

    func testDays() {
        let now = Date()
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-86400), to: now), "1d")
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-604800), to: now), "7d")
    }

    func testMonths() {
        let now = Date()
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-2592000), to: now), "1mo")
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(-7776000), to: now), "3mo")
    }

    func testFutureDateReturnsEmpty() {
        let now = Date()
        XCTAssertEqual(CopilotSession.formatRelativeAge(from: now.addingTimeInterval(60), to: now), "")
    }

    func testRelativeAgeProperty() {
        let now = Date()
        let session = CopilotSession(
            id: "test", topic: "test", fullMessage: "", branch: "", turns: 0,
            lastTimestamp: now.addingTimeInterval(-3600), status: .done,
            pid: nil, tty: nil, terminalType: .unknown
        )
        XCTAssertEqual(session.relativeAge, "1h")
    }

    func testRelativeAgeNilTimestamp() {
        let session = CopilotSession(
            id: "test", topic: "test", fullMessage: "", branch: "", turns: 0,
            lastTimestamp: nil, status: .done,
            pid: nil, tty: nil, terminalType: .unknown
        )
        XCTAssertEqual(session.relativeAge, "")
    }
}
