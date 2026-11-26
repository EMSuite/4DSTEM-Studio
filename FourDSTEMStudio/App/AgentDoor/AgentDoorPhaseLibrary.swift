//
//  AgentDoorPhaseLibrary.swift
//  Role: the agent door's tools for the shared phase library (#513), as Electron Microscopy Studio's: `list_phases` reads My
//        Phases (each phase's id, name, source and credit, lattice, whether edited; records that could not be read; a fetch still
//        running and the last one's outcome), and `fetch_phase` adds a Materials Project entry by its id through the Add Phase
//        sheet's own model (`AddPhaseModel`: the same download, the same conversion to the conventional cell, the same record),
//        and can then use it as a phase of Map Phases or as ACOM's phase model. `add_phase` and `set_acom` take a library phase
//        by `phase_id` too.
//
//        THE KEY NEVER PASSES THE DOOR: no tool takes or answers an API key. A download uses the person's own key from the
//        Keychain when Settings holds one, as the sheet does, and the open service otherwise.
//

import Foundation
import ShellAgentDoor
import ShellPhaseLibrary
import DiffractoCore
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    /// A fetch_phase still running, or the last one's outcome, as list_phases reports it.
    @MainActor final class PhaseFetches {
        static let shared = PhaseFetches()
        private(set) var running: String?
        private(set) var last: [String: Any]?
        /// The download in flight, so a test can wait for it.
        private(set) var task: Task<Void, Never>?

        /// Adds `id` to the library through the sheet's model and, with `use`, uses it in `state`'s window.
        func fetch(_ id: String, use: LibraryPhaseUse?, in state: AppState?) {
            running = id
            let model = AddPhaseModel(library: PhaseServices.library, client: PhaseServices.client, keyStore: PhaseServices.keyStore)
            model.selection = id
            task = Task { @MainActor [weak state] in
                await model.loadPreview()
                defer { running = nil }
                switch model.preview {
                case .failed(_, let message):
                    last = ["id": id, "added": false, "problem": message]
                case .ready:
                    do {
                        let phase = model.isInLibrary ? PhaseServices.library.phase(materialsProjectID: id) : try model.add()
                        guard let phase else {
                            last = ["id": id, "added": false, "problem": "The entry could not be read."]
                            return
                        }
                        if let use, let state { state.useLibraryPhase(phase, as: use) }
                        last = ["id": id, "added": true, "used_as": AgentJSON.orNull(use?.rawValue),
                                "phase": Mac4DSTEMAgentDoor.libraryPhase(phase)]
                    } catch {
                        last = ["id": id, "added": false, "problem": "The phase could not be saved: \(error.localizedDescription)"]
                    }
                default:
                    last = ["id": id, "added": false, "problem": "The entry could not be read."]
                }
            }
        }
    }

    static let phaseLibraryTools: [AgentTool] = [
        AgentTool(name: "list_phases", title: "My Phases",
                  summary: "The phases of the library on this Mac (My Phases, shared with the Add Phase sheet): id (a Materials "
                      + "Project id, or the CIF's model id), name, source and credit, the lattice (a, b, c in Å, angles in degrees) "
                      + "and whether it was edited; records that could not be read; a fetch_phase still running and the last "
                      + "one's outcome. add_phase and set_acom take a phase by its id.",
                  input: .noWindow) { _ in
            guard PhaseServices.isLoaded else { return libraryLoading }
            let library = PhaseServices.library
            return .json([
                "phases": library.phases.map(libraryPhase),
                "unreadable": library.unreadable,
                "fetching": AgentJSON.orNull(PhaseFetches.shared.running),
                "last_fetch": AgentJSON.orNull(PhaseFetches.shared.last),
            ] as [String: Any])
        },
        AgentTool(name: "fetch_phase", title: "Fetch a phase from the Materials Project",
                  summary: "Adds a Materials Project entry to My Phases by its id (mp-81), as the Add Phase sheet does: the open "
                      + "service, or the person's own key when Settings holds one (no tool takes or shows a key). use phase also "
                      + "adds it to Map Phases, use acom makes it ACOM's phase model. It answers at once; list_phases says "
                      + "fetching until the entry is read, then the outcome.",
                  input: .window,
                  parameters: [
                      AgentParameter("material_id", .text, summary: "The Materials Project id, such as mp-81.", required: true),
                      AgentParameter("use", .choice(LibraryPhaseUse.allCases.map(\.rawValue)),
                                     summary: "phase: add it to Map Phases; acom: make it ACOM's phase model. Leave out to only "
                                         + "add it to My Phases."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.agentBusy else { return busyRefusal }
            guard PhaseServices.isLoaded else { return libraryLoading }
            let id = (call.arguments["material_id"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard id.range(of: #"^(mp|mvc)-[0-9]+$"#, options: .regularExpression) != nil else {
                return .refusal(status: 400, message: "material_id must be a Materials Project id such as mp-81, not \(id).")
            }
            if PhaseFetches.shared.running != nil {
                return .refusal(status: 409, message: "A fetch is running; list_phases says when it ends.")
            }
            let use = call.arguments["use"].flatMap(LibraryPhaseUse.init(rawValue:))
            if let existing = PhaseServices.library.phase(materialsProjectID: id) {
                if let use { state.useLibraryPhase(existing, as: use) }
                state.statusText = "An agent used \(quotedAgentText(existing.name)) from My Phases."
                return .json(["fetching": false, "already_in_library": true, "used_as": AgentJSON.orNull(use?.rawValue),
                              "phase": libraryPhase(existing)] as [String: Any])
            }
            PhaseFetches.shared.fetch(id, use: use, in: state)
            state.statusText = "An agent fetched \(id) from the Materials Project."
            return .json(["fetching": id])
        },
    ]

    /// Refused until the library has been read at launch, so no answer is made from an empty library.
    static let libraryLoading = AgentToolOutput.refusal(status: 503, message: "The phase library is still being read; ask again in a moment.")

    /// A library phase by `id`, or the refusal that names what the library holds.
    static func libraryPhase(id: String) -> Result<Phase, ToolRefusal> {
        guard PhaseServices.isLoaded else { return .failure(ToolRefusal(status: 503, message: "The phase library is still being read; ask again in a moment.")) }
        guard let phase = PhaseServices.library.phases.first(where: { $0.id == id }) else {
            return .failure(ToolRefusal(status: 404, message: "No phase \(id) in My Phases; list_phases names them, fetch_phase adds one."))
        }
        return .success(phase)
    }

    /// One phase as list_phases gives it.
    static func libraryPhase(_ p: Phase) -> [String: Any] {
        let cell = p.structure().cell
        let source: String = switch p.source {
        case .materialsProject: "materials_project"
        case .cif(let fileName): "cif \(fileName)"
        }
        return [
            "id": p.id, "name": p.name, "source": source, "credit": AgentJSON.orNull(p.source.attribution),
            "lattice": ["a": cell.a, "b": cell.b, "c": cell.c, "alpha": cell.alphaDeg, "beta": cell.betaDeg, "gamma": cell.gammaDeg],
            "edited": p.isEdited,
        ]
    }
}
