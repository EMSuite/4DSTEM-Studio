//
//  AgentDoorMaterialsProjectTests.swift
//  The agent door's Materials Project tools (App/AgentDoor/AgentDoorMaterialsProject.swift, issue #297), over a real door with a
//  stub transport: fetch, read the result and verdict, import as a phase; a mismatch is refused; no key is said in words; the key
//  never appears in an answer.
//

import XCTest
import ShellAgentDoor
import DSTEMSession
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorMaterialsProjectTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    private var keep: [AppState] = []
    private static let secret = "test-key-0123456789"

    private struct Stub: MaterialsProjectTransport {
        let body: String
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let url = request.url ?? URL(string: "https://api.materialsproject.org/")!
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    private static let aluminium = """
    {"data": [{"material_id": "mp-134", "formula_pretty": "Al",
      "structure": {"lattice": {"a": 4.0495, "b": 4.0495, "c": 4.0495, "alpha": 90, "beta": 90, "gamma": 90},
        "sites": [{"species": [{"element": "Al", "occu": 1.0}], "abc": [0.0, 0.0, 0.0]},
                  {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.5, 0.5, 0.0]},
                  {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.5, 0.0, 0.5]},
                  {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.0, 0.5, 0.5]}]},
      "symmetry": {"crystal_system": "cubic", "symbol": "Fm-3m", "number": 225, "point_group": "m-3m", "hall": "-F 4 2 3"}}],
     "errors": []}
    """

    override func setUp() async throws {
        defaultsSuite = "agent-door-mp-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0,
                         defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.phaseTools + Mac4DSTEMAgentDoor.materialsProjectTools)
        door.setEnabled(true)
        door.runsAllowed = true
        Mac4DSTEMAgentDoor.materialsProjectTransport = Stub(body: Self.aluminium)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
    }

    override func tearDown() async throws {
        Mac4DSTEMAgentDoor.materialsProjectTransport = URLSessionTransport()
        Mac4DSTEMAgentDoor.materialsProjectFetches.removeAll()
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

    private func window(key: String?) -> AppState {
        let state = AppState(materialsProject: MaterialsProjectSettings(store: InMemoryAPIKeyStore(initial: key)))
        keep.append(state)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        return state
    }

    private func lastFetch(when done: Bool = true) async throws -> [String: Any] {
        let end = Date().addingTimeInterval(20)
        while true {
            let text = try await call("get_materials_project").text
            XCTAssertFalse(text.contains(Self.secret), "the key never leaves through the door")
            let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
            if let fetch = answer["last_fetch"] as? [String: Any], fetch["running"] as? Bool == false { return fetch }
            if Date() > end { XCTFail("the fetch did not finish: \(text)"); return [:] }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Mutation: the import skipping the verdict, or the fetch not stored - red.
    func testAnAgentFetchesChecksAndImportsAPhase() async throws {
        let state = window(key: Self.secret)
        let fetch = try await call("fetch_materials_project", ["material_id": "mp-134", "expected_formula": "Al",
                                                              "expected_space_group": 225])
        XCTAssertFalse(fetch.refused, fetch.text)
        let done = try await lastFetch()
        XCTAssertEqual(done["verdict"] as? String, "matches")
        XCTAssertEqual(done["can_import"] as? Bool, true)
        XCTAssertEqual((done["material"] as? [String: Any])?["space_group_number"] as? Int, 225)

        let imported = try await call("import_materials_project", ["as": "phase"])
        XCTAssertFalse(imported.refused, imported.text)
        XCTAssertEqual(state.phaseMapping.phases.count, 1)
        XCTAssertFalse(state.activityLog.messages.contains { $0.contains(Self.secret) }, "nor in the Output")

        _ = try await call("fetch_materials_project", ["material_id": "mp-134", "expected_space_group": 191])
        let mismatch = try await lastFetch()
        XCTAssertEqual(mismatch["verdict"] as? String, "mismatch")
        let refused = try await call("import_materials_project")
        XCTAssertTrue(refused.refused, "a mismatch blocks the import, as in the sheet")
        XCTAssertEqual(state.phaseMapping.phases.count, 1)
    }

    /// Mutation: a fetch with no stored key not said in words - red.
    func testNoKeyIsSaidAndNothingIsSent() async throws {
        _ = window(key: nil)
        let read = try await call("get_materials_project")
        let stored = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(read.text.utf8)) as? [String: Any], read.text)
        XCTAssertEqual(stored["api_key_stored"] as? Bool, false)
        XCTAssertTrue(stored["last_fetch"] is NSNull)
        _ = try await call("fetch_materials_project", ["material_id": "mp-134"])
        let done = try await lastFetch()
        XCTAssertTrue((done["blocked_because"] as? String)?.contains("Settings") == true, "\(done)")
        let bad = try await call("fetch_materials_project", ["material_id": "aluminium"])
        XCTAssertTrue(bad.refused)
    }
}
