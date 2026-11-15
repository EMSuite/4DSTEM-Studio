//
//  AppState+RunGuard.swift
//  Role: Ask before closing the window, opening another file in it or quitting stops a running analysis (#313; HIG, "unsaved
//        work"). Nothing is asked when no analysis runs, and a dataset load in flight keeps its own refusal. The question is
//        `RunInterruptionDialog` on the window; the close comes from `WindowCloseGuard`, the quit from `RunGuard` (the app delegate).
//

import AppKit
import DSTEMSession
import Foundation

/// What the question is about: the action that would stop the run.
enum RunInterruption: Equatable {
    case close
    case open(URL, configure: Bool)
    case quit
}

extension AppState {
    /// An analysis whose work would be lost: a cancellable run that is not the dataset's own load, and not a session-file save
    /// (an open during a save keeps its own refusal, "Still saving the session file").
    var analysisIsRunning: Bool {
        isBusy && activeOperation != nil && !datasetSession.isLoading && !SessionSidecarLocator.isSaveInFlight(activeOperation)
    }

    /// True when the action waits for the question (an analysis runs); false when it may go ahead now.
    @discardableResult
    func askBeforeInterruptingRun(_ action: RunInterruption) -> Bool {
        guard analysisIsRunning else { return false }
        pendingRunInterruption = action
        return true
    }

    /// A session-file save is in flight: closing or quitting would cancel it unwritten, so both wait for it, as an open does.
    var sessionSaveIsInFlight: Bool {
        isBusy && SessionSidecarLocator.isSaveInFlight(activeOperation)
    }

    /// The window's close button or ⌘W (`WindowCloseGuard`): true closes now. Refused during a session-file save.
    func windowShouldClose() -> Bool {
        if sessionSaveIsInFlight {
            statusText = "Still saving the session file — close the window when the save finishes"
            return false
        }
        return !askBeforeInterruptingRun(.close)
    }

    /// "Stop and …": the run stops, as the window's own close always stopped it (`windowClosed`), then the action goes ahead.
    func confirmRunInterruption() {
        guard let action = pendingRunInterruption else { return }
        pendingRunInterruption = nil
        switch action {
        case .close:
            operationCenter.reset()
            closeWindowWithoutAsking?()
        case .open(let url, let configure):
            operationCenter.reset()
            if configure { openFileForConfiguration(url: url) } else { openFile(url: url) }
        case .quit:
            RunGuard.answerQuit(stopRuns: true)
        }
    }

    /// Cancel: nothing happens and the run goes on.
    func dismissRunInterruption() {
        guard let action = pendingRunInterruption else { return }
        pendingRunInterruption = nil
        if action == .quit { RunGuard.answerQuit(stopRuns: false) }
    }
}

/// The question's sentences, as pure functions (a view describes UI only).
enum RunInterruptionWording {
    static func title(operation: String?) -> String {
        "Stop \(operation ?? "the Running Analysis")?"
    }

    static func confirmButton(_ action: RunInterruption) -> String {
        switch action {
        case .close: "Stop and Close"
        case .open: "Stop and Open"
        case .quit: "Stop and Quit"
        }
    }

    static func message(_ action: RunInterruption, operation: String?) -> String {
        let run = operation.map { "\($0) is still running" } ?? "An analysis is still running"
        let lost = "what it has computed so far is lost."
        switch action {
        case .close: return "\(run). Closing the window stops it, and \(lost)"
        case .open(let url, _): return "\(run). Opening \(url.lastPathComponent) stops it, and \(lost)"
        case .quit: return "\(run). Quitting mac4DSTEM stops it, and \(lost)"
        }
    }
}

/// The open dataset windows, for Quit: the app delegate asks the first window that runs an analysis, and the answer stops the runs
/// of every window (or keeps them all). AppKit's `applicationShouldTerminate` because SwiftUI has no quit confirmation.
@MainActor
enum RunGuard {
    private final class Entry { weak var state: AppState?; init(_ state: AppState) { self.state = state } }
    private static var windows: [Entry] = []
    private static var quitReply: ((Bool) -> Void)?

    static func enroll(_ state: AppState) {
        windows.removeAll { $0.state == nil || $0.state === state }
        windows.append(Entry(state))
    }

    static func withdraw(_ state: AppState) {
        windows.removeAll { $0.state == nil || $0.state === state }
    }

    /// `applicationShouldTerminate`: quit now, or ask the first window that runs an analysis and quit on its answer (`reply`).
    static func shouldTerminate(reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        // A session-file save in flight: quitting would cancel it unwritten. Refused, as an open or a close is.
        if let saving = windows.compactMap(\.state).first(where: \.sessionSaveIsInFlight) {
            saving.statusText = "Still saving the session file — quit when the save finishes"
            return .terminateCancel
        }
        guard let running = windows.compactMap(\.state).first(where: \.analysisIsRunning) else { return .terminateNow }
        quitReply = reply
        running.pendingRunInterruption = .quit
        return .terminateLater
    }

    /// The quit question was answered: stop every window's run and quit, or keep everything.
    static func answerQuit(stopRuns: Bool) {
        if stopRuns { for state in windows.compactMap(\.state) where state.analysisIsRunning { state.operationCenter.reset() } }
        let reply = quitReply
        quitReply = nil
        reply?(stopRuns)
    }
}
