import XCTest
@testable import CopilotSessionsLib

final class CopilotSessionTests: XCTestCase {
    // MARK: - Status properties

    func testWorkingSessionIsActive() {
        let s = makeSession(status: .working)
        XCTAssertTrue(s.isActive)
        XCTAssertEqual(s.statusEmoji, "🟡")
        XCTAssertEqual(s.statusLabel, "Working")
    }

    func testWaitingSessionIsActive() {
        let s = makeSession(status: .waiting)
        XCTAssertTrue(s.isActive)
        XCTAssertEqual(s.statusEmoji, "🟢")
        XCTAssertEqual(s.statusLabel, "Waiting for input")
    }

    func testDoneSessionNotActive() {
        let s = makeSession(status: .done)
        XCTAssertFalse(s.isActive)
        XCTAssertEqual(s.statusEmoji, "⚪")
        XCTAssertEqual(s.statusLabel, "Done")
    }

    // MARK: - Display label

    func testDisplayLabelShowsTopicWhenPresent() {
        let s = makeSession(topic: "Fix the build")
        XCTAssertEqual(s.displayLabel, "Fix the build")
    }

    func testDisplayLabelFallsBackToShortId() {
        let s = makeSession(id: "abcdef123456-7890-rest", topic: "")
        XCTAssertEqual(s.displayLabel, "abcdef123456")
    }

    // MARK: - Short ID

    func testShortIdIsTwelveChars() {
        let s = makeSession(id: "00f3a96e-cba2-4831-84e3-ac13938d7ef3")
        XCTAssertEqual(s.shortId, "00f3a96e-cba")
    }

    // MARK: - Terminal type icons

    func testTerminalTypeIcons() {
        XCTAssertEqual(TerminalType.terminal.icon, "🖥️")
        XCTAssertEqual(TerminalType.kitty.icon, "🐱")
        XCTAssertEqual(TerminalType.iterm2.icon, "🔲")
        XCTAssertEqual(TerminalType.ghostty.icon, "👻")
        XCTAssertEqual(TerminalType.wezterm.icon, "🌐")
        XCTAssertEqual(TerminalType.alacritty.icon, "⬛")
        XCTAssertEqual(TerminalType.unknown.icon, "💻")
    }

    func testTerminalTypeRawValues() {
        XCTAssertEqual(TerminalType.terminal.rawValue, "Terminal")
        XCTAssertEqual(TerminalType.kitty.rawValue, "kitty")
        XCTAssertEqual(TerminalType.iterm2.rawValue, "iTerm2")
    }

    // MARK: - Helpers

    private func makeSession(
        id: String = "test-id-0000-0000-000000000000",
        topic: String = "Test topic",
        fullMessage: String = "Test full message",
        branch: String = "main",
        turns: Int = 5,
        status: SessionStatus = .waiting,
        pid: String? = "12345",
        tty: String? = "ttys001",
        terminalType: TerminalType = .terminal
    ) -> CopilotSession {
        CopilotSession(
            id: id, topic: topic, fullMessage: fullMessage, branch: branch,
            turns: turns, lastTimestamp: Date(), status: status,
            pid: pid, tty: tty, terminalType: terminalType
        )
    }
}
