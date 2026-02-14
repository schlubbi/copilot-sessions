import XCTest
@testable import CopilotSessionsLib

final class SessionSortingTests: XCTestCase {
    private func statusOrder(_ s: SessionStatus) -> Int {
        switch s {
        case .working: return 0
        case .waiting: return 1
        case .done:    return 2
        }
    }

    func testSortsByStatusPriority() {
        let now = Date()
        let sessions: [CopilotSession] = [
            makeSession(topic: "Done", status: .done, time: now),
            makeSession(topic: "Waiting", status: .waiting, time: now),
            makeSession(topic: "Working", status: .working, time: now),
        ]

        let sorted = sessions.sorted { (a: CopilotSession, b: CopilotSession) -> Bool in
            if a.status != b.status {
                return statusOrder(a.status) < statusOrder(b.status)
            }
            return (a.lastTimestamp ?? .distantPast) > (b.lastTimestamp ?? .distantPast)
        }

        XCTAssertEqual(sorted[0].topic, "Working")
        XCTAssertEqual(sorted[1].topic, "Waiting")
        XCTAssertEqual(sorted[2].topic, "Done")
    }

    func testSortsByTimestampWithinStatus() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        let sessions: [CopilotSession] = [
            makeSession(topic: "Old", status: .waiting, time: earlier),
            makeSession(topic: "New", status: .waiting, time: now),
        ]

        let sorted = sessions.sorted { (a: CopilotSession, b: CopilotSession) -> Bool in
            if a.status != b.status {
                return statusOrder(a.status) < statusOrder(b.status)
            }
            return (a.lastTimestamp ?? .distantPast) > (b.lastTimestamp ?? .distantPast)
        }

        XCTAssertEqual(sorted[0].topic, "New")
        XCTAssertEqual(sorted[1].topic, "Old")
    }

    func testStatusEnumCases() {
        let all: [SessionStatus] = [.working, .waiting, .done]
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(SessionStatus.working.rawValue, "working")
        XCTAssertEqual(SessionStatus.waiting.rawValue, "waiting")
        XCTAssertEqual(SessionStatus.done.rawValue, "done")
    }

    private func makeSession(
        topic: String, status: SessionStatus, time: Date
    ) -> CopilotSession {
        CopilotSession(
            id: UUID().uuidString, topic: topic, fullMessage: topic, branch: "main",
            turns: 1, lastTimestamp: time, status: status,
            pid: nil, tty: nil, terminalType: .unknown
        )
    }
}
