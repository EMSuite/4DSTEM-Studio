//
//  AgentDoorEDSTests.swift
//  The Spectroscopy room's EDS tools through a real door over MCP (issue #254): a window that holds a spectrum image and no 4D
//  scan moves to the room, picks elements, quantifies with run_eds and with run_task, and reads the room's table as numbers.
//

import XCTest
import ShellAgentDoor
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorEDSTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    private var keep: [AppState] = []

    override func setUp() async throws {
        defaultsSuite = "agent-door-eds-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0,
                         defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.allTools)
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

    private func waitUntilIdle(_ state: AppState, timeout: TimeInterval = 60) async throws {
        let end = Date().addingTimeInterval(timeout)
        while state.edx.isBusy || state.isBusy {
            if Date() > end { return XCTFail("the EDS room stayed busy") }
            try await Task.sleep(for: .milliseconds(20))
        }
        await state.edx.settled()
    }

    /// A spectrum image alone: the room's tools pick, quantify and read the table; run_task presses the same Quantify.
    /// Mutation: the EDS tools not registered, or run_task refusing a window with no 4D scan in the room - red.
    func testAnAgentQuantifiesASpectrumImageAloneAndReadsTheNumbers() async throws {
        let loaded = try SpectroQuantFixtures.image()
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(loaded)
        let end = Date().addingTimeInterval(60)
        while state.edx.isBusy || state.edx.autoID == .idle {   // the open's own Auto ID, as EDSToolbarBusyTests waits for it
            if Date() > end { return XCTFail("the open's Auto ID did not land") }
            try await Task.sleep(for: .milliseconds(20))
        }
        if loaded.metadata.beamEnergyKeV == nil { state.edx.changeMethod { $0.beamEnergyKeV = 200 } }
        try await waitUntilIdle(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        XCTAssertFalse(state.hasDataset, "no 4D scan in this window")

        let look = try await call("get_eds")
        XCTAssertFalse(look.refused, look.text)
        XCTAssertNotNil(try object(look.text)["picks"], "get_eds reads the room")

        let gated = try await call("set_eds", ["add": "Al"])
        XCTAssertTrue(gated.refused, "set_eds acts, so it waits for Let agents run analyses")

        door.runsAllowed = true
        let room = try await call("select_task", ["workspace": "spectroscopy"])
        XCTAssertFalse(room.refused, room.text)
        XCTAssertEqual(state.navigation.workspaceArea, .spectroscopy)

        let picked = try await call("set_eds", ["remove": state.edx.picks.map(\.symbol).joined(separator: ","),
                                                "add": "Al, Mg, Si, Cu", "region": "whole"])
        XCTAssertFalse(picked.refused, picked.text)
        try await waitUntilIdle(state)
        XCTAssertEqual(Set(state.edx.picks.map(\.symbol)), ["Al", "Mg", "Si", "Cu"])

        let quantify = try await call("run_eds", ["action": "quantify"])
        XCTAssertFalse(quantify.refused, quantify.text)
        try await waitUntilIdle(state)
        let table = try object(try await call("get_eds").text)
        let csv = try XCTUnwrap(table["results_csv"] as? String, "the table, as numbers, once Quantify has run: \(table)")
        XCTAssertEqual(csv, state.edx.resultsCSV, "the table is the room's own CSV")
        XCTAssertTrue(csv.contains("Al"), csv)

        let run = try await call("run_task")
        XCTAssertFalse(run.refused, "run_task presses Quantify on a spectrum image alone: \(run.text)")
        XCTAssertEqual(try object(run.text)["started"] as? String, "Quantify")
        try await waitUntilIdle(state)
        XCTAssertNotNil(state.edx.fit, state.edx.fitFailure ?? "")
    }

    /// A window with no spectrum image: the room's tools say so in words.
    func testAWindowWithNoSpectrumImageIsRefusedInWords() async throws {
        let state = AppState(); keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let look = try await call("get_eds")
        XCTAssertTrue(look.refused)
        XCTAssertTrue(look.text.contains("spectrum image"), look.text)
    }
}
