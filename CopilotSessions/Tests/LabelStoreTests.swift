import XCTest
@testable import CopilotSessionsLib

final class LabelStoreTests: XCTestCase {
    var tmpFile: String!
    var store: LabelStore!

    override func setUp() {
        super.setUp()
        tmpFile = NSTemporaryDirectory() + "copilot-labels-test-\(UUID().uuidString).json"
        store = LabelStore(path: tmpFile)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpFile)
        super.tearDown()
    }

    func testInitiallyEmpty() {
        XCTAssertNil(store.label(for: "any-session"))
        XCTAssertTrue(store.allLabeledSessionIds.isEmpty)
    }

    func testSetAndGetLabel() {
        store.setLabel("My Label", for: "session-1")
        XCTAssertEqual(store.label(for: "session-1"), "My Label")
        XCTAssertTrue(store.allLabeledSessionIds.contains("session-1"))
    }

    func testClearLabel() {
        store.setLabel("My Label", for: "session-1")
        store.setLabel(nil, for: "session-1")
        XCTAssertNil(store.label(for: "session-1"))
        XCTAssertFalse(store.allLabeledSessionIds.contains("session-1"))
    }

    func testClearWithEmptyString() {
        store.setLabel("My Label", for: "session-1")
        store.setLabel("", for: "session-1")
        XCTAssertNil(store.label(for: "session-1"))
    }

    func testMultipleSessions() {
        store.setLabel("Label A", for: "session-a")
        store.setLabel("Label B", for: "session-b")
        XCTAssertEqual(store.label(for: "session-a"), "Label A")
        XCTAssertEqual(store.label(for: "session-b"), "Label B")
        XCTAssertEqual(store.allLabeledSessionIds.count, 2)
    }

    func testPersistenceAcrossInstances() {
        store.setLabel("Persistent", for: "session-x")

        // Create a new instance reading the same file
        let store2 = LabelStore(path: tmpFile)
        XCTAssertEqual(store2.label(for: "session-x"), "Persistent")
    }

    func testOverwriteLabel() {
        store.setLabel("First", for: "session-1")
        store.setLabel("Second", for: "session-1")
        XCTAssertEqual(store.label(for: "session-1"), "Second")
    }

    func testNonexistentFileDoesNotCrash() {
        let store3 = LabelStore(path: "/tmp/nonexistent-\(UUID().uuidString).json")
        XCTAssertNil(store3.label(for: "any"))
    }
}
