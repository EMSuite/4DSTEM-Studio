//
//  PhaseLibraryUseTests.swift
//  #513: the phases come from the shared EMSuiteUI phase library (My Phases), as in Electron Microscopy Studio. A library phase
//  becomes one of the window's models with the importers' symmetry rule (the Lane F-B row 6 family check, which the app's own
//  Materials Project importer carried, now runs on every library phase), goes to Map Phases or ACOM as the Add Phase sheet
//  sends it, resolves from the library when a saved phase list names it, and is reached by the door's list_phases,
//  fetch_phase, add_phase and set_acom by id. No test downloads anything.
//

import XCTest
import DiffractoCore
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
import ShellPhaseLibrary
@testable import FourDSTEMStudio

@MainActor
final class PhaseLibraryUseTests: XCTestCase {
    private var folder: URL!
    private var door: AgentDoor?
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "phase-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await PhaseServices.useLibrary(PhaseLibrary(store: PhaseLibraryStore(folder: folder)))
    }

    override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        if !defaultsSuite.isEmpty { UserDefaults().removePersistentDomain(forName: defaultsSuite) }
        try? FileManager.default.removeItem(at: folder)
    }

    private func materialsProjectPhase(_ id: String, _ name: String, _ structure: CrystalStructure) -> Phase {
        Phase(id: id, name: name, source: .materialsProject(id: id, fetched: Date(timeIntervalSince1970: 1_790_000_000)),
              structure: structure)
    }

    private func keep(_ phase: Phase) throws {
        try PhaseServices.library.add(phase, source: Data("{}".utf8), sourceExtension: "json")
    }

    // MARK: - The model (Lane F-B row 6, now on library phases)

    /// Pa-3 (pyrite-type, Laue m-3): a cubic metric whose 4-fold axis is missing imports Unreduced, never cubic.
    /// Mutation: the library model takes its symmetry from the metric alone - red.
    func testACubicMetricWithoutAFourFoldIsNeverCubic() {
        let u = 0.385
        let fe: [SIMD3<Double>] = [[0, 0, 0], [0, 0.5, 0.5], [0.5, 0, 0.5], [0.5, 0.5, 0]]
        let s: [SIMD3<Double>] = [
            [u, u, u], [-u + 0.5, -u, u + 0.5], [-u, u + 0.5, -u + 0.5], [u + 0.5, -u + 0.5, -u],
            [-u, -u, -u], [u + 0.5, u, -u + 0.5], [u, -u + 0.5, u + 0.5], [-u + 0.5, u + 0.5, u],
        ].map { $0 - $0.rounded(.down) }
        let structure = CrystalStructure.detectingSymmetry(
            cell: UnitCell(a: 5.42, b: 5.42, c: 5.42, alphaDeg: 90, betaDeg: 90, gammaDeg: 90),
            sites: fe.map { AtomSite(z: 26, fractional: $0) } + s.map { AtomSite(z: 16, fractional: $0) })
        let model = PhaseServices.crystalModel(materialsProjectPhase("mp-226", "FeS2", structure))
        XCTAssertEqual(model.symmetry, .identity, "Pa-3 is not m-3m: Unreduced, never .cubic")
        XCTAssertEqual(model.structure.laueClass, .mThreeBar)
        XCTAssertFalse(model.supportsOrientationMapping)
    }

    /// Control: hcp Mg is hexagonal. A Materials Project phase is named with its id and carries the credit.
    func testAMaterialsProjectPhaseIsNamedWithItsIDAndCredited() {
        let model = PhaseServices.crystalModel(materialsProjectPhase("mp-153", "Mg", CrystalPresets.magnesium))
        XCTAssertEqual(model.symmetry, .hexagonal)
        XCTAssertEqual(model.id, "mp-153")
        XCTAssertEqual(model.displayName, "Mg (mp-153)")
        XCTAssertEqual(model.source, .materialsProject)
        XCTAssertEqual(model.extraProvenance["materials_project_id"], "mp-153")
        XCTAssertEqual(model.extraProvenance["materials_project_credit"], "Materials Project · mp-153 · CC BY 4.0")
    }

    // MARK: - The window

    /// Mutation: a phase chosen for ACOM is also added to Map Phases, or one chosen as a phase changes ACOM's crystal - red.
    func testAPhaseGoesWhereTheSheetSendsIt() {
        let state = AppState()
        let gold = materialsProjectPhase("mp-81", "Au", CrystalPresets.gold)
        state.useLibraryPhase(gold, as: .acom)
        XCTAssertEqual(state.acomSession.modelSelection, .imported("mp-81"))
        XCTAssertTrue(state.phaseMapping.phases.isEmpty)
        XCTAssertEqual(state.acomSession.importedCrystalModels.map(\.id), ["mp-81"])

        let iron = materialsProjectPhase("mp-13", "Fe", CrystalPresets.iron)
        state.useLibraryPhase(iron, as: .phase)
        XCTAssertEqual(state.phaseMapping.phases.map(\.model.id), ["mp-13"])
        XCTAssertEqual(state.acomSession.modelSelection, .imported("mp-81"), "ACOM's crystal stays (mac4DSTEM#312)")
        state.useLibraryPhase(gold, as: .phase)
        XCTAssertEqual(state.acomSession.importedCrystalModels.map(\.id), ["mp-81", "mp-13"], "each model held once")
    }

    /// A saved phase list naming a library phase resolves in a window that does not hold it, and the window then holds it.
    /// Mutation: the restore reads the window's models alone - red (structure missing).
    func testASavedPhaseListResolvesFromTheLibrary() throws {
        let iron = materialsProjectPhase("mp-13", "Fe", CrystalPresets.iron)
        try keep(iron)
        let first = AppState()
        first.useLibraryPhase(iron, as: .phase)
        let record = PhaseSetupRecord(phases: first.phaseMapping.phases, reference: first.phaseMapping.reference,
                                      matching: first.phaseMapping.matching, cifSources: [:])

        let second = AppState()
        guard case .failure = record.restored(held: second.acomSession.importedCrystalModels) else {
            return XCTFail("premise: the window alone does not hold it")
        }
        guard case .success(let setup) = record.restored(held: second.heldAndLibraryCrystalModels) else {
            return XCTFail("the library holds it")
        }
        XCTAssertEqual(setup.phases.map(\.model.id), ["mp-13"])
        XCTAssertTrue(second.holdLibraryPhase(id: "mp-13"))
        XCTAssertEqual(second.acomSession.importedCrystalModels.map(\.id), ["mp-13"])
        XCTAssertFalse(second.holdLibraryPhase(id: "mp-999"), "not in the library")
    }

    // MARK: - The door

    private func openDoor() async throws -> AppState {
        defaultsSuite = "phase-library-door-\(UUID().uuidString)"
        let door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0,
                             defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.phaseTools + Mac4DSTEMAgentDoor.phaseLibraryTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { throw XCTSkip("the door did not open") }
        self.door = door
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        return state
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, json: [String: Any], text: String) {
        guard let door, case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ])
        let (data, _) = try await session.data(for: request)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        return (result["isError"] as? Bool ?? true, json, text)
    }

    /// list_phases names the library; add_phase takes a phase by id; fetch_phase uses one already kept without downloading and
    /// refuses an id that is no Materials Project id. Mutation: add_phase requires a path, or fetch_phase downloads a kept
    /// phase again - red.
    func testTheDoorListsAddsAndFetchesByID() async throws {
        let state = try await openDoor()
        try keep(materialsProjectPhase("mp-13", "Fe", CrystalPresets.iron))
        try keep(materialsProjectPhase("mp-81", "Au", CrystalPresets.gold))

        let listed = try await call("list_phases")
        XCTAssertFalse(listed.refused, listed.text)
        let phases = try XCTUnwrap(listed.json["phases"] as? [[String: Any]], listed.text)
        XCTAssertEqual(Set(phases.compactMap { $0["id"] as? String }), ["mp-13", "mp-81"])
        XCTAssertEqual(phases.first { $0["id"] as? String == "mp-13" }?["source"] as? String, "materials_project")
        XCTAssertFalse(listed.text.lowercased().contains("api_key"), "no key passes the door")

        let added = try await call("add_phase", ["phase_id": "mp-13"])
        XCTAssertFalse(added.refused, added.text)
        XCTAssertEqual(state.phaseMapping.phases.map(\.model.id), ["mp-13"])
        let unknown = try await call("add_phase", ["phase_id": "mp-999"])
        XCTAssertTrue(unknown.refused)
        XCTAssertTrue(unknown.text.contains("list_phases"), unknown.text)
        let neither = try await call("add_phase")
        XCTAssertTrue(neither.refused)

        let kept = try await call("fetch_phase", ["material_id": "mp-81", "use": "acom"])
        XCTAssertFalse(kept.refused, kept.text)
        XCTAssertEqual(kept.json["already_in_library"] as? Bool, true, kept.text)
        XCTAssertEqual(state.acomSession.modelSelection, .imported("mp-81"))
        let notAnID = try await call("fetch_phase", ["material_id": "gold"])
        XCTAssertTrue(notAnID.refused)
        withExtendedLifetime(state) {}
    }
}
