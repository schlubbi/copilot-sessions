import XCTest
@testable import CopilotSessionsLib

final class RepositoryGroupingTests: XCTestCase {
    func testDisplayRepoNameFromRepository() {
        let session = makeSession(repository: "github/github", cwd: "/Users/x/src/github/github")
        XCTAssertEqual(session.displayRepoName, "github/github")
    }

    func testDisplayRepoNameFallsToCwd() {
        let session = makeSession(repository: "", cwd: "/Users/x/src/github/copilot-sessions")
        XCTAssertEqual(session.displayRepoName, "github/copilot-sessions")
    }

    func testDisplayRepoNameShortCwd() {
        let session = makeSession(repository: "", cwd: "/myproject")
        XCTAssertEqual(session.displayRepoName, "myproject")
    }

    func testDisplayRepoNameRootCwd() {
        let session = makeSession(repository: "", cwd: "/")
        XCTAssertEqual(session.displayRepoName, "")
    }

    func testDisplayRepoNameEmpty() {
        let session = makeSession(repository: "", cwd: "")
        XCTAssertEqual(session.displayRepoName, "")
    }

    func testGroupingByRepo() {
        let sessions = [
            makeSession(topic: "A", repository: "github/github"),
            makeSession(topic: "B", repository: "github/github"),
            makeSession(topic: "C", repository: "schlubbi/copilot-sessions"),
            makeSession(topic: "D", repository: ""),
        ]

        let grouped = Dictionary(grouping: sessions) {
            $0.displayRepoName.isEmpty ? "Other" : $0.displayRepoName
        }

        XCTAssertEqual(grouped["github/github"]?.count, 2)
        XCTAssertEqual(grouped["schlubbi/copilot-sessions"]?.count, 1)
        XCTAssertEqual(grouped["Other"]?.count, 1)
    }

    func testGroupsSortByMostRecent() {
        let now = Date()
        let sessions = [
            makeSession(topic: "Old", repository: "old/repo", time: now.addingTimeInterval(-86400)),
            makeSession(topic: "New", repository: "new/repo", time: now),
        ]

        let grouped = Dictionary(grouping: sessions) { $0.displayRepoName }
        let sorted = grouped.sorted { a, b in
            let aMax = a.value.compactMap(\.lastTimestamp).max() ?? .distantPast
            let bMax = b.value.compactMap(\.lastTimestamp).max() ?? .distantPast
            return aMax > bMax
        }

        XCTAssertEqual(sorted[0].key, "new/repo")
        XCTAssertEqual(sorted[1].key, "old/repo")
    }

    private func makeSession(
        topic: String = "Test",
        repository: String = "",
        cwd: String = "",
        time: Date = Date()
    ) -> CopilotSession {
        CopilotSession(
            id: UUID().uuidString, topic: topic, fullMessage: "", branch: "main",
            turns: 1, lastTimestamp: time, status: .waiting,
            pid: nil, tty: nil, terminalType: .unknown,
            repository: repository, cwd: cwd
        )
    }
}
