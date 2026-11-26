//
//  AgentDoorPersonTests.swift
//  The tools for controls that were the person's (App/AgentDoor/AgentDoorPerson.swift, issue #297), asked through a real door
//  over MCP: Settings read and set (the agents' own switches not among them), Clear Calibration, Try Demo Data, and the refusals
//  in words when there is nothing to do.
//

import XCTest
import ShellAgentDoor
import DSTEMSession
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorPersonTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    private var keep: [AppState] = []

    override func setUp() async throws {
        defaultsSuite = "agent-door-person-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0,
                         defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.personTools)
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

    private func window() -> AppState {
        let state = AppState(); keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        return state
    }

    /// Mutation: set_settings writing nothing, or offering an agents switch - red.
    func testSettingsAreReadAndSetButNotTheAgentsOwn() async throws {
        let state = window()
        let read = try object(try await call("get_settings").text)
        let settings = try XCTUnwrap(read["settings"] as? [String: Any])
        XCTAssertEqual(settings["show_scale_bar"] as? Bool, state.preferences.showScaleBar)
        XCTAssertNotNil(read["agents"] as? [String: Any])

        let gated = try await call("set_settings", ["show_scale_bar": !state.preferences.showScaleBar])
        XCTAssertTrue(gated.refused, "set_settings acts")

        door.runsAllowed = true
        let before = state.preferences.showScaleBar
        let set = try await call("set_settings", ["show_scale_bar": !before, "figure_format": ExportFigureFormat.pdf.rawValue])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.preferences.showScaleBar, !before)
        XCTAssertEqual(state.preferences.figureFormat, .pdf)
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent set Settings:") })

        let names = Set(Mac4DSTEMAgentDoor.SettingSpec.all.map(\.parameter.name))
        XCTAssertFalse(names.contains { $0.contains("agent") }, "the agents switches stay the person's: \(names)")
    }

    /// Mutation: clear_calibration not calling Clear Calibration, not refusing an empty calibration, or clearing without
    /// confirm - red.
    func testClearCalibrationClearsAndRefusesWhenThereIsNothing() async throws {
        let state = window()
        door.runsAllowed = true
        let nothing = try await call("clear_calibration")
        XCTAssertTrue(nothing.refused)
        XCTAssertTrue(nothing.text.contains("no calibration"), nothing.text)

        await state.openDemoFixture()   // calibrated
        XCTAssertTrue(state.calibrationSession.hasAnyCalibrationValue)
        let unconfirmed = try await call("clear_calibration")
        XCTAssertTrue(unconfirmed.refused, "Clear Calibration asks first, so the door needs confirm")
        XCTAssertTrue(unconfirmed.text.contains("confirm true"), unconfirmed.text)
        XCTAssertNotNil(state.calibrationSession.calibration.qPixelSize, "nothing cleared without confirm")
        let cleared = try await call("clear_calibration", ["confirm": true])
        XCTAssertFalse(cleared.refused, cleared.text)
        XCTAssertFalse(state.calibrationSession.calibration.hasFittedOrigin)
        XCTAssertNil(state.calibrationSession.calibration.qPixelSize)
    }

    /// Mutation: open_demo not opening, or the refusals missing - red.
    func testTheDemoOpensAndTheOthersSayWhyNot() async throws {
        let state = window()
        door.runsAllowed = true
        let demo = try await call("open_demo")
        XCTAssertFalse(demo.refused, demo.text)
        let end = Date().addingTimeInterval(60)
        while !state.hasDataset || state.isBusy || state.datasetSession.isLoading {
            if Date() > end { return XCTFail("the demo did not open") }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent opened the demo data.") })

        // #314: the demo is held by default, so release_cube releases it; a cube not in memory is refused in words.
        let wasResident = state.residency.isResident
        let release = try await call("release_cube")
        if wasResident {
            XCTAssertFalse(release.refused, release.text)
            XCTAssertFalse(state.residency.isResident, "release_cube left the cube in memory")
        } else {
            XCTAssertTrue(release.refused, "a cube not in memory is refused in words")
        }
        let model = try await call("remove_learned_model")
        if state.learnedDetection.activeModel == nil { XCTAssertTrue(model.text.contains("bundled"), model.text) }
        let reopen = try await call("reopen_without_session")
        XCTAssertTrue(reopen.refused, "the demo has no session to set aside: \(reopen.text)")
    }

    /// Mutation: open_demo replacing an open dataset without confirm - red.
    func testTheDemoOverAnOpenDatasetNeedsConfirm() async throws {
        let state = window()
        door.runsAllowed = true
        await state.openDemoFixture()
        let path = try XCTUnwrap(state.descriptor?.filePath)
        let unconfirmed = try await call("open_demo")
        XCTAssertTrue(unconfirmed.refused, "replacing an open dataset loses what is not saved: \(unconfirmed.text)")
        XCTAssertTrue(unconfirmed.text.contains("confirm true"), unconfirmed.text)
        XCTAssertEqual(state.descriptor?.filePath, path)
        XCTAssertFalse(state.activityLog.messages.contains { $0.contains("An agent opened the demo data.") })

        let confirmed = try await call("open_demo", ["confirm": true])
        XCTAssertFalse(confirmed.refused, confirmed.text)
        let end = Date().addingTimeInterval(60)
        while state.isBusy || state.datasetSession.isLoading {
            if Date() > end { return XCTFail("the demo did not open again") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
