//
//  AgentDoorPolishTests.swift
//  Answers from the door runs that disagreed with the window (issues #266, #323), asked through a real door over MCP: busy is
//  one answer in list_windows and get_window and holds from open_file's answer on; a step that failed after it started says why
//  in operation.error until the next begins; scan_summary is said, not left out.
//

import XCTest
import ShellAgentDoor
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorPolishTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    private var keep: [AppState] = []

    override func setUp() async throws {
        defaultsSuite = "agent-door-polish-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0,
                         defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.runTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
    }

    override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, text: String) {
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ])
        let (data, _) = try await session.data(for: request)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any], String(decoding: data, as: UTF8.self))
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (result["isError"] as? Bool ?? true, text)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    /// Mutation: list_windows or get_window reading `isBusy` alone - red (an agent's open in flight reads idle).
    func testBusyIsOneAnswerAndHoldsWhileAnAgentsOpenIsInFlight() async throws {
        let state = AppState(); keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        XCTAssertFalse(state.agentBusy)

        XCTAssertTrue(state.claimOpen())   // what open_file does from its answer on
        let windows = try await call("list_windows")
        let listed = try XCTUnwrap((try object(windows.text)["windows"] as? [[String: Any]])?.first, windows.text)
        XCTAssertEqual(listed["busy"] as? Bool, true, "list_windows")
        let window = try object(try await call("get_window").text)
        XCTAssertEqual(window["busy"] as? Bool, true, "get_window")
        let operation = try XCTUnwrap(window["operation"] as? [String: Any])
        XCTAssertEqual(operation["busy"] as? Bool, true, "operation.busy")
        XCTAssertEqual(operation["name"] as? String, "Opening")

        door.runsAllowed = true
        let refused = try await call("select_scan_position", ["x": 0, "y": 0])
        XCTAssertTrue(refused.refused)
        XCTAssertTrue(refused.text.contains("busy"), "a tool that acts waits, as get_window says: \(refused.text)")

        state.releaseOpenClaim()
        let after = try await call("get_window")
        XCTAssertEqual(try object(after.text)["busy"] as? Bool, false)
    }

    /// Mutation: operation.error reading `errorMessage` alone - red (the failure is only in the status text).
    func testAStepThatFailedAfterItStartedSaysWhyInOperationError() async throws {
        let state = AppState(); keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        state.presentComputeFailure(SimpleError("The fit annulus holds no ring."))
        let failedWindow = try await call("get_window")
        let failed = try XCTUnwrap(try object(failedWindow.text)["operation"] as? [String: Any])
        XCTAssertEqual(failed["error"] as? String, "The fit annulus holds no ring.")

        let token = state.beginCancellableOperation("Fit Ellipse", status: "Fitting…")
        let nextWindow = try await call("get_window")
        let next = try XCTUnwrap(try object(nextWindow.text)["operation"] as? [String: Any])
        XCTAssertTrue(next["error"] is NSNull, "the next step begins with no error: \(next)")
        state.finishCancellableOperation(token)
    }

    /// Mutation: the key left out when no whole-scan detection has finished - red.
    func testScanSummaryIsSaidWhenNoDetectionHasFinished() async throws {
        let state = AppState(); keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let window = try await call("get_window")
        let disks = try XCTUnwrap(try object(window.text)["disk_detection"] as? [String: Any])
        XCTAssertTrue(disks.keys.contains("scan_summary"))
        XCTAssertTrue(disks["scan_summary"] is NSNull)
    }
}
