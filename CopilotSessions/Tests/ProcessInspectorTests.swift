import XCTest
@testable import CopilotSessionsLib

final class ProcessInspectorTests: XCTestCase {
    // MARK: - isWorking with mock PPID maps

    func testNoChildrenNotWorking() {
        let map: [pid_t: [pid_t]] = [:]
        // PID that doesn't exist — no children, 0 CPU
        XCTAssertFalse(ProcessInspector.isWorking(999999, ppidMap: map))
    }

    func testMcpChildrenOnlyNotWorking() {
        // Simulate: copilot (pid 100) has children npm (200) and node (300)
        // isWorking checks processName of children, but 200/300 don't exist
        // so processName returns nil → not a tool child → falls to CPU check
        let map: [pid_t: [pid_t]] = [100: [200, 300]]
        // PID 100 doesn't exist, so CPU is 0 → not working
        XCTAssertFalse(ProcessInspector.isWorking(100, ppidMap: map))
    }

    // MARK: - processName

    func testProcessNameOfSelf() {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let name = ProcessInspector.processName(myPid)
        XCTAssertNotNil(name)
        // The test runner binary name varies but should be non-empty
        XCTAssertFalse(name!.isEmpty)
    }

    func testProcessNameOfInvalidPid() {
        let name = ProcessInspector.processName(999999)
        XCTAssertNil(name)
    }

    // MARK: - buildPpidMap

    func testBuildPpidMapNotEmpty() {
        let map = ProcessInspector.buildPpidMap()
        // Should contain at least launchd (pid 1) as a parent
        XCTAssertFalse(map.isEmpty, "PPID map should not be empty on a running system")
    }

    func testBuildPpidMapContainsSelf() {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let map = ProcessInspector.buildPpidMap()
        // Our process should appear as a child of our parent
        let parentHasUs = map.values.contains { children in
            children.contains(myPid)
        }
        XCTAssertTrue(parentHasUs, "PPID map should contain our PID as a child")
    }

    // MARK: - cpuUsagePercent

    func testCpuUsageOfSelf() {
        let myPid = ProcessInfo.processInfo.processIdentifier
        // We're actively running, so CPU should be >= 0
        let cpu = ProcessInspector.cpuUsagePercent(myPid, window: 0.01)
        XCTAssertGreaterThanOrEqual(cpu, 0.0)
    }

    func testCpuUsageOfInvalidPid() {
        let cpu = ProcessInspector.cpuUsagePercent(999999, window: 0.01)
        XCTAssertEqual(cpu, 0.0)
    }

    // MARK: - detectTerminal

    func testDetectTerminalOfSelfReturnsKnownOrUnknown() {
        // The test process is launched by swift test / xctest, not a terminal
        let myPid = ProcessInfo.processInfo.processIdentifier
        let term = ProcessInspector.detectTerminal(myPid)
        // Should return something — probably .unknown for test runner
        XCTAssertNotNil(term)
    }

    func testDetectTerminalOfInvalidPid() {
        let term = ProcessInspector.detectTerminal(999999)
        XCTAssertEqual(term, .unknown)
    }

    // MARK: - mcpNames

    func testMcpNamesContainsExpected() {
        XCTAssertTrue(ProcessInspector.mcpNames.contains("npm"))
        XCTAssertTrue(ProcessInspector.mcpNames.contains("node"))
        XCTAssertTrue(ProcessInspector.mcpNames.contains("azmcp"))
        XCTAssertFalse(ProcessInspector.mcpNames.contains("bash"))
        XCTAssertFalse(ProcessInspector.mcpNames.contains("git"))
    }
}
