//
//  AgentDoorViewTests.swift
//  The agent door's view tool (App/AgentDoor/AgentDoorView.swift, issue #297), over a real door: zoom on a pane that is on
//  screen, refused on one that is not; orientation, mirror, fit overlay and Same scale set and read back in get_window.
//

import XCTest
import ShellAgentDoor
import ShellControls
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorViewTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    private var keep: [AnyObject] = []

    override func setUp() async throws {
        defaultsSuite = "agent-door-view-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0,
                         defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.viewTools)
        door.setEnabled(true)
        door.runsAllowed = true
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

    /// Mutation: set_view ignoring zoom, or zooming a pane that is not there - red.
    func testZoomActsOnAPaneOnScreenOnly() async throws {
        let state = AppState(); keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let absent = try await call("set_view", ["pane": "result", "zoom": "in"])
        XCTAssertTrue(absent.refused)
        XCTAssertTrue(absent.text.contains("not on screen"), absent.text)

        let pane = PaneZoomModel(); keep.append(pane)
        pane.box = CGSize(width: 400, height: 400)
        state.paneZooms.result = pane   // what the result pane does on appear
        let zoomed = try await call("set_view", ["pane": "result", "zoom": "in"])
        XCTAssertFalse(zoomed.refused, zoomed.text)
        XCTAssertEqual(pane.state.effectiveZoom, 2, accuracy: 1e-9)
        let display = try XCTUnwrap(try object(zoomed.text)["zoom"] as? [String: Any])
        XCTAssertEqual(display["result"] as? Double ?? 0, 2, accuracy: 1e-9)
        XCTAssertTrue(display["pattern"] is NSNull)

        _ = try await call("set_view", ["pane": "result", "zoom": "fit"])
        XCTAssertEqual(pane.state.effectiveZoom, 1, accuracy: 1e-9)
    }

    /// Mutation: a display setting not written, or not in get_window - red.
    func testDisplaySettingsAreSetAndReadBack() async throws {
        let state = AppState(); keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let set = try await call("set_view", ["orientation": "90", "mirrored": true, "fit_overlay": false, "same_scale": true])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.realSpaceDisplayOrientation, .quarterTurn)
        XCTAssertTrue(state.realSpaceDisplayMirrored)
        XCTAssertFalse(state.showFitOverlay)
        XCTAssertTrue(state.comparisonSameScale)
        let windowAnswer = try await call("get_window")
        let view = try XCTUnwrap(try object(windowAnswer.text)["view"] as? [String: Any])
        let display = try XCTUnwrap(view["display"] as? [String: Any])
        XCTAssertEqual(display["orientation_degrees"] as? Int, 90)
        XCTAssertEqual(display["same_scale"] as? Bool, true)
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent set the view:") })

        let bad = try await call("set_view", ["zoom": "in"])
        XCTAssertTrue(bad.refused, "zoom needs a pane")
    }
}
