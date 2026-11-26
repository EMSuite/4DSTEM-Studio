//
//  LibraryAddPhaseSheet.swift
//  Role: the shared Add Phase sheet (EMSuiteUI ShellPhaseViews, #513), as Electron Microscopy Studio shows it: search the
//        Materials Project, or pick from My Phases; Open CIF… hands back to the caller's own file dialog after the sheet has
//        closed. A phase chosen goes to Map Phases or to ACOM's phase model through `AppState.useLibraryPhase(_:as:)`, the
//        path the door's fetch_phase takes too.
//

import SwiftUI
import ShellPhaseLibrary
import ShellPhaseViews

struct LibraryAddPhaseSheet: ViewModifier {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    let use: LibraryPhaseUse
    /// Opens the caller's CIF dialog; it runs once the sheet is down.
    let onOpenCIF: () -> Void
    @State private var model = AddPhaseModel(library: PhaseServices.library, client: PhaseServices.client,
                                             keyStore: PhaseServices.keyStore)

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            AddPhaseSheet(model: model, onOpenCIF: onOpenCIF) { phase in
                appState.useLibraryPhase(phase, as: use)
            }
        }
    }
}

extension View {
    /// The Add Phase sheet while `isPresented`; a chosen phase is used `as` given.
    func libraryAddPhaseSheet(isPresented: Binding<Bool>, as use: LibraryPhaseUse, onOpenCIF: @escaping () -> Void) -> some View {
        modifier(LibraryAddPhaseSheet(isPresented: isPresented, use: use, onOpenCIF: onOpenCIF))
    }
}
