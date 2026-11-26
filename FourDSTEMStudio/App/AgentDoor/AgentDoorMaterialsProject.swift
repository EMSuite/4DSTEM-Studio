//
//  AgentDoorMaterialsProject.swift
//  Role: The agent door's Materials Project tools (issue #297): an agent fetches a material by its mp-id, checks it against an
//        expected formula and space group, reads the result and imports it as a phase or as ACOM's phase model, as the Materials
//        Project sheet does (`UI/MaterialsProjectImportSheet.swift`, `AppState.fetchMaterialsProject`).
//
//  The request uses the key the person stored in Settings. The key never passes through the door: no tool reads, returns, sets or
//  logs it, and saving or removing it stays the person's. A fetch goes online, so it acts (behind "Let agents run analyses").
//

import Foundation
import ShellAgentDoor
import DiffractoCore
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    /// A window's last Materials Project fetch, as the sheet holds it.
    enum MaterialsProjectFetch {
        case fetching(String)
        case done(String, MaterialsProjectFetchOutcome)
    }

    /// Each window's last fetch, by window.
    static var materialsProjectFetches: [ObjectIdentifier: MaterialsProjectFetch] = [:]

    /// The transport fetches use: the network, or a stub in tests.
    static var materialsProjectTransport: any MaterialsProjectTransport = URLSessionTransport()

    static let materialsProjectTools: [AgentTool] = [
        AgentTool(name: "fetch_materials_project", title: "Fetch from Materials Project",
                  summary: "Fetches a material from Materials Project by its id (mp-…), as the Materials Project sheet's Fetch does, "
                      + "with the key the person stored in Settings, and checks it against the formula and space group you expect. "
                      + "It answers at once; get_materials_project holds the result, and import_materials_project imports it.",
                  input: .window,
                  parameters: [
                      AgentParameter("material_id", .text, summary: "The Materials Project id, e.g. mp-134.", required: true),
                      AgentParameter("expected_formula", .text, summary: "The formula you expect, e.g. Al2CuLi; a mismatch "
                                         + "blocks the import, as in the sheet."),
                      AgentParameter("expected_space_group", .integer(1...230), summary: "The space group number you expect."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            let id = (call.arguments["material_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ObjectIdentifier(state)
            if case .fetching? = materialsProjectFetches[key] {
                return .refusal(status: 409, message: "A fetch is running; wait until get_materials_project says it is done.")
            }
            let formula = call.arguments["expected_formula"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectation = PhaseExpectation(formula: formula?.isEmpty == false ? formula : nil,
                                               spaceGroupNumber: call.arguments["expected_space_group"].flatMap(Int.init))
            guard id.range(of: "^mp-[0-9]+$", options: .regularExpression) != nil else {
                return .refusal(status: 400, message: "A Materials Project id is mp- followed by digits, e.g. mp-134.")
            }
            materialsProjectFetches[key] = .fetching(id)
            state.statusText = "An agent fetched \(id) from Materials Project."
            let transport = materialsProjectTransport
            Task { [weak state] in
                guard let state else { return }
                let outcome = await state.fetchMaterialsProject(materialID: id, expectation: expectation, transport: transport)
                materialsProjectFetches[key] = .done(id, outcome)
            }
            return .json(["fetching": id])
        },
        AgentTool(name: "get_materials_project", title: "Materials Project result",
                  summary: "Whether the person has stored a Materials Project key (never the key), and the window's last fetch: running, or the material (formula, space group, cell, "
                      + "deprecated), the verdict against what you expected and whether it may be imported; or why it failed "
                      + "(no key stored, not found, rate limited, ...).",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            // Whether a key is stored, as Settings' status row says; never the key.
            return .json(["api_key_stored": state.materialsProject.hasKey,
                          "last_fetch": materialsProjectFetches[ObjectIdentifier(state)].map(materialsProjectSummary) ?? NSNull()])
        },
        AgentTool(name: "import_materials_project", title: "Import from Materials Project",
                  summary: "Imports the fetched material, as the sheet's Import does: as a phase of Map Phases (as, phase) or as "
                      + "ACOM's phase model (as, acom). Refused while the verdict is a mismatch or the fetch failed.",
                  input: .window,
                  parameters: [AgentParameter("as", .choice(["phase", "acom"]), summary: "Where the model goes (default phase).")],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.agentBusy else { return busyRefusal }
            guard case .done(_, let outcome)? = materialsProjectFetches[ObjectIdentifier(state)] else {
                return .refusal(status: 409, message: "No finished fetch: fetch_materials_project, then wait for "
                    + "get_materials_project.")
            }
            guard canImport(outcome: outcome), case .fetched(_, let model, _, _) = outcome else {
                return .refusal(status: 409, message: (materialsProjectSummary(.done("", outcome))["blocked_because"] as? String)
                    ?? "This fetch cannot be imported.")
            }
            let asPhase = call.arguments["as"] != "acom"
            state.importFetchedCrystalModel(model, addAsPhaseSlot: asPhase)
            state.statusText = "An agent imported “\(model.displayName)” from Materials Project "
                + (asPhase ? "as a phase." : "as ACOM's phase model.")
            return asPhase ? .json(phaseMappingSettings(of: state)) : .json(["acom_phase_model": model.displayName])
        },
    ]

    /// A fetch as an agent reads it. Never holds the key.
    static func materialsProjectSummary(_ fetch: MaterialsProjectFetch) -> [String: Any] {
        switch fetch {
        case .fetching(let id):
            return ["material_id": id, "running": true]
        case .done(let id, let outcome):
            var out: [String: Any] = ["material_id": id, "running": false, "can_import": canImport(outcome: outcome)]
            switch outcome {
            case .noAPIKey:
                out["blocked_because"] = "No Materials Project API key is stored. Ask the person to add theirs in \(AppName.display)'s "
                    + "Settings; the door never handles the key."
            case .failure(let message):
                out["blocked_because"] = message
            case .fetched(let document, let model, let verdict, let fetchedAt):
                let cell = model.structure.cell
                out["material"] = [
                    "name": model.displayName,
                    "formula": AgentJSON.orNull(document.formulaPretty),
                    "space_group_symbol": AgentJSON.orNull(document.symmetry?.symbol),
                    "space_group_number": AgentJSON.orNull(document.symmetry?.number),
                    "crystal_system": AgentJSON.orNull(document.symmetry?.crystalSystem),
                    "cell_angstrom_degrees": [cell.a, cell.b, cell.c, cell.alphaDeg, cell.betaDeg, cell.gammaDeg],
                    "deprecated": document.deprecated ?? false,
                    "fetched_at": ISO8601DateFormatter().string(from: fetchedAt),
                ] as [String: Any]
                switch verdict {
                case .matches: out["verdict"] = "matches"
                case .unchecked: out["verdict"] = "unchecked (no expectation given)"
                case .mismatch(let reason):
                    out["verdict"] = "mismatch"
                    out["blocked_because"] = reason
                }
            }
            return out
        }
    }
}
