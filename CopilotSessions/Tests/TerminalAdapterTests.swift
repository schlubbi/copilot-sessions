import XCTest
@testable import CopilotSessionsLib

final class TerminalAdapterTests: XCTestCase {
    // MARK: - Protocol conformance

    func testAppleTerminalProperties() {
        let adapter = AppleTerminalAdapter()
        XCTAssertEqual(adapter.key, "terminal")
        XCTAssertEqual(adapter.name, "Terminal")
        XCTAssertEqual(adapter.icon, "🖥️")
    }

    func testKittyProperties() {
        let adapter = KittyAdapter()
        XCTAssertEqual(adapter.key, "kitty")
        XCTAssertEqual(adapter.name, "kitty")
        XCTAssertEqual(adapter.icon, "🐱")
    }

    func testITermProperties() {
        let adapter = ITermAdapter()
        XCTAssertEqual(adapter.key, "iterm2")
        XCTAssertEqual(adapter.name, "iTerm2")
        XCTAssertEqual(adapter.icon, "🔲")
    }

    // MARK: - Availability

    func testAppleTerminalAlwaysAvailable() {
        XCTAssertTrue(AppleTerminalAdapter().isAvailable())
    }

    // MARK: - allTerminalAdapters registry

    func testAllAdaptersContainsThree() {
        XCTAssertEqual(allTerminalAdapters.count, 3)
    }

    func testAllAdaptersHaveUniqueKeys() {
        let keys = allTerminalAdapters.map { $0.key }
        XCTAssertEqual(Set(keys).count, keys.count, "Adapter keys should be unique")
    }

    func testAllAdaptersHaveUniqueNames() {
        let names = allTerminalAdapters.map { $0.name }
        XCTAssertEqual(Set(names).count, names.count, "Adapter names should be unique")
    }

    // MARK: - detectTerminalAdapter

    func testDetectReturnsAdapter() {
        let adapter = detectTerminalAdapter()
        // Should return kitty (if installed) or Terminal
        XCTAssertTrue(adapter.key == "kitty" || adapter.key == "terminal")
    }

    func testDetectFallsBackToTerminal() {
        // If kitty is not available, should return Terminal
        let adapter = detectTerminalAdapter()
        if !KittyAdapter().isAvailable() {
            XCTAssertEqual(adapter.key, "terminal")
        }
    }

    // MARK: - ISO8601 parsing

    func testParseISO8601WithFractionalSeconds() {
        let ds = SessionDataSource()
        let date = ds.parseISO8601("2026-02-13T23:39:36.875Z")
        XCTAssertNotNil(date)
    }

    func testParseISO8601WithoutFractionalSeconds() {
        let ds = SessionDataSource()
        let date = ds.parseISO8601("2026-02-13T23:39:36Z")
        XCTAssertNotNil(date)
    }

    func testParseISO8601InvalidReturnsNil() {
        let ds = SessionDataSource()
        let date = ds.parseISO8601("not-a-date")
        XCTAssertNil(date)
    }

    func testParseISO8601EmptyReturnsNil() {
        let ds = SessionDataSource()
        XCTAssertNil(ds.parseISO8601(""))
    }
}
