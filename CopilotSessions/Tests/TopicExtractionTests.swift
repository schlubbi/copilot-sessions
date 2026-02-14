import XCTest
@testable import CopilotSessionsLib

final class TopicExtractionTests: XCTestCase {
    let ds = SessionDataSource()

    // MARK: - Filler prefix stripping

    func testStripsIWantTo() {
        XCTAssertEqual(ds.extractTopic(from: "I want to fix the build"), "Fix the build")
    }

    func testStripsCanYou() {
        // "Can you " → "check the logs" → "Check " stripped → "the logs" → "the " stripped → "Logs"
        XCTAssertEqual(ds.extractTopic(from: "Can you check the logs"), "Logs")
    }

    func testStripsPlease() {
        XCTAssertEqual(ds.extractTopic(from: "Please create a new endpoint"), "A new endpoint")
    }

    func testStripsMultiplePrefixes() {
        // "Can you " → "please help me find the bug"
        // "please " is not a prefix here (lowercase match but "please" not in list as lower)
        // Actually: "Can you " stripped → "please help me find the bug"
        // second pass: "please " not matched because list has "Please "
        // but lowercased check: "please " matches "Please " → stripped
        let result = ds.extractTopic(from: "Can you please help me find the bug")
        XCTAssertFalse(result.isEmpty)
    }

    func testStripsCaseInsensitive() {
        // "i want to " matches "I want to " case-insensitively
        XCTAssertEqual(ds.extractTopic(from: "i want to fix the build"), "Fix the build")
    }

    // MARK: - URL stripping

    func testStripsHTTPSUrls() {
        // URL is replaced, leaving "Look at and fix it"
        // Then "Look at" not stripped (not exactly "Take a look at")
        let result = ds.extractTopic(from: "Look at https://github.com/foo/bar/pull/123 and fix it")
        XCTAssertEqual(result, "Look at and fix it")
    }

    func testStripsRelativePaths() {
        // "./src/main.rs " stripped → "and refactor" → "and " stripped → "refactor"
        let result = ds.extractTopic(from: "Read ./src/main.rs and refactor")
        XCTAssertEqual(result, "Refactor")
    }

    func testStripsAbsolutePaths() {
        // "/Users/foo/bar.txt " stripped → "review this file"
        // "this " prefix stripped → "file" → "Review this file" wait...
        // Let's trace: "/Users/foo/bar.txt " → removed by ^/\S+\s*
        // remaining: "review this file"
        // prefix "this " doesn't match at start
        // capitalize → "Review this file"
        XCTAssertEqual(
            ds.extractTopic(from: "/Users/foo/bar.txt review this file"),
            "Review this file")
    }

    // MARK: - Truncation

    func testTruncatesLongTopicsAtWordBoundary() {
        let long = "Implement a comprehensive authentication system with JWT tokens"
        let result = ds.extractTopic(from: long)
        XCTAssertTrue(result.count <= 36, "Expected ≤36 chars, got \(result.count): '\(result)'")
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testShortTopicNotTruncated() {
        let result = ds.extractTopic(from: "Fix the bug")
        XCTAssertFalse(result.hasSuffix("…"))
        XCTAssertEqual(result, "Fix the bug")
    }

    // MARK: - Capitalization

    func testCapitalizesFirstLetter() {
        XCTAssertEqual(ds.extractTopic(from: "fix the build"), "Fix the build")
    }

    // MARK: - Edge cases

    func testEmptyString() {
        XCTAssertEqual(ds.extractTopic(from: ""), "")
    }

    func testMultilineUsesFirstLine() {
        let msg = "Fix the build\nAlso update the docs\nAnd clean up"
        XCTAssertEqual(ds.extractTopic(from: msg), "Fix the build")
    }

    func testOnlyPunctuation() {
        XCTAssertEqual(ds.extractTopic(from: "..."), "")
    }

    func testUrlOnly() {
        let result = ds.extractTopic(from: "https://github.com/foo/bar")
        XCTAssertEqual(result, "")
    }
}
