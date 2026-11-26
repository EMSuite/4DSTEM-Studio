//
//  PhaseServices.swift
//  Role: the phases come from the shared EMSuiteUI phase library (#513), as in Electron Microscopy Studio: the Materials Project
//        through its open OPTIMADE service by default (the person's own key from the Keychain when Settings holds one), the
//        person's CIFs, and My Phases, the library on this Mac. The app's own Materials Project import, its key store and its
//        settings pane are gone. A library phase becomes one of the window's held models (`acomSession.importedCrystalModels`),
//        so Map Phases, ACOM and Q from crystal take it as they take an imported CIF, and a saved session that names it by id
//        resolves it from the library on reopen.
//
//  The built-in crystals (`CrystalModelLibrary`) are no choice in any picker; they stay a resolver for sessions and recipes
//  saved with their ids (`al_fcc` and the others).
//

import Foundation
import ShellLayout
import ShellPhaseLibrary
import DiffractoCore
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

enum PhaseServices {
    // Variables only so a test can hand in a stub transport and a temporary folder; the app never reassigns them.
    static var keyStore: any APIKeyStore = KeychainAPIKeyStore()
    static var client = MaterialsProjectClient()
    static var library = PhaseLibrary(store: PhaseLibraryStore.standard()
        ?? PhaseLibraryStore(folder: FileManager.default.temporaryDirectory.appending(path: "Phases", directoryHint: .isDirectory)))
    private static var loadStarted = false
    /// The library has been read from disk; the agent door's phase tools answer only then.
    static var isLoaded = false

    /// Reads the library from disk once per launch; later calls return at once.
    static func loadLibrary() async {
        guard !loadStarted else { return }
        loadStarted = true
        await library.load()
        isLoaded = true
    }

    /// A test's library in place of this Mac's: read, and the door's phase tools answer from it.
    static func useLibrary(_ replacement: PhaseLibrary) async {
        library = replacement
        loadStarted = true
        await replacement.load()
        isLoaded = true
    }

    /// A library phase as the app's model: its id, its name (a Materials Project entry with its id beside the formula), its
    /// structure and the symmetry the importers' rule reduces it to; the Materials Project's credit rides in the provenance.
    static func crystalModel(_ phase: Phase) -> CrystalModel {
        let structure = phase.structure()
        var provenance: [String: String] = [:]
        let source: CrystalModelSource
        let name: String
        switch phase.source {
        case .materialsProject(let id, let fetched):
            source = .materialsProject
            name = phase.name == id ? id : "\(phase.name) (\(id))"
            provenance["materials_project_id"] = id
            provenance["materials_project_fetched"] = ISO8601DateFormatter().string(from: fetched)
            if let credit = phase.source.attribution { provenance["materials_project_credit"] = credit }
        case .cif:
            source = .imported
            name = phase.name
        }
        if phase.isEdited { provenance["phase_library_edited"] = "true" }
        return CrystalModel(id: phase.id, displayName: name, structure: structure,
                            symmetry: ACOMCrystalSymmetry.reduction(for: structure), source: source,
                            spaceGroupNumber: structure.spaceGroupNumber, extraProvenance: provenance)
    }

    /// Every library phase as a model, for a saved session's phases to resolve against.
    static var libraryModels: [CrystalModel] { isLoaded ? library.phases.map { crystalModel($0) } : [] }

    /// A CIF's text as the library keeps it, when the phase came from one: a saved session then carries the text too.
    static func cifSource(of phase: Phase) -> PhaseSetupRecord.CIFSource? {
        guard case .cif(let fileName) = phase.source, let url = library.sourceFile(of: phase.id),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return PhaseSetupRecord.CIFSource(text: text, fileBaseName: (fileName as NSString).deletingPathExtension)
    }
}

/// Where a library phase goes in a window.
enum LibraryPhaseUse: String, CaseIterable, Sendable {
    /// A phase of Map Phases.
    case phase
    /// ACOM's phase model, which Q from crystal also reads.
    case acom
}

extension AppState {
    /// Holds `model` among the window's models (by id: a newer copy replaces the older).
    func holdCrystalModel(_ model: CrystalModel) {
        if let index = acomSession.importedCrystalModels.firstIndex(where: { $0.id == model.id }) {
            acomSession.importedCrystalModels[index] = model
        } else {
            acomSession.importedCrystalModels.append(model)
        }
    }

    /// The window's models and the library's, each id once (the window's first): what a saved phase list resolves against.
    var heldAndLibraryCrystalModels: [CrystalModel] {
        let held = acomSession.importedCrystalModels
        let ids = Set(held.map(\.id))
        return held + PhaseServices.libraryModels.filter { !ids.contains($0.id) }
    }

    /// A phase of the library, chosen in the Add Phase sheet or by the door: held, then added to Map Phases or made ACOM's
    /// phase model. Added as a phase, ACOM's crystal stays as it was (mac4DSTEM#312).
    @discardableResult
    func useLibraryPhase(_ phase: Phase, as use: LibraryPhaseUse) -> CrystalModel {
        let model = PhaseServices.crystalModel(phase)
        holdCrystalModel(model)
        if let cif = PhaseServices.cifSource(of: phase) { acomSession.importedCIFSources[model.id] = cif }
        switch use {
        case .acom:
            acomSession.modelSelection = .imported(model.id)
            statusText = "ACOM's phase model is \"\(model.displayName)\" from My Phases"
        case .phase:
            statusText = "Added phase \"\(model.displayName)\" from My Phases"
            addPhaseMappingSlot(model)
        }
        return model
    }

    /// Holds a library phase a saved recipe names by id, so the replay finds it among the window's models; false when the
    /// library has none.
    @discardableResult
    func holdLibraryPhase(id: String) -> Bool {
        guard !acomSession.importedCrystalModels.contains(where: { $0.id == id }) else { return true }
        guard let phase = PhaseServices.library.phases.first(where: { $0.id == id }) else { return false }
        holdCrystalModel(PhaseServices.crystalModel(phase))
        if let cif = PhaseServices.cifSource(of: phase) { acomSession.importedCIFSources[id] = cif }
        return true
    }

    /// A CIF opened from the Add Phase sheet: imported as Import CIF does (its text kept for the session file), then kept in My
    /// Phases with its bytes under the same id, so it is there in the next window and in Electron Microscopy Studio's sense of the
    /// library. Saving it in the library is best effort: a failure is said and the import stands.
    @discardableResult
    func importCIFIntoLibrary(from url: URL, as use: LibraryPhaseUse) -> CrystalModel? {
        guard let model = importCrystalModel(from: url, selectsForOrientation: use == .acom) else { return nil }
        if use == .phase { addPhaseMappingSlot(model) }
        guard !PhaseServices.library.phases.contains(where: { $0.id == model.id }),
              let text = acomSession.importedCIFSources[model.id]?.text else { return model }
        let phase = Phase(id: model.id, name: model.displayName, source: .cif(fileName: url.lastPathComponent), structure: model.structure)
        do {
            try PhaseServices.library.add(phase, source: Data(text.utf8), sourceExtension: "cif")
        } catch {
            activityLog.record("\(url.lastPathComponent) is imported but not kept in My Phases: \(error.localizedDescription)")
        }
        return model
    }

    /// Adds a phase slot by `PhaseMappingProduct.add(_:)`'s rule and says so when the structure was already in the list. The Add
    /// Phase menu, the sheet and the door share the one rule.
    func addPhaseMappingSlot(_ model: CrystalModel) {
        if phaseMapping.add(model) {
            statusText = "Added \"\(model.displayName)\" again — give this copy its own zone axis"
        }
    }
}
