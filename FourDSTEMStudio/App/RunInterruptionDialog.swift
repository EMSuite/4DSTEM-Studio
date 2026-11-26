//
//  RunInterruptionDialog.swift
//  Role: The question "Stop <analysis>?" before closing the window, opening another file in it or quitting stops a running
//        analysis (#313). Hosted on the dataset window, like `ReopenWithoutSessionDialog`; the flag it shows is
//        `AppState.pendingRunInterruption`. `WindowCloseGuard` asks it for the window's close button and ⌘W.
//

import AppKit
import SwiftUI

private struct RunInterruptionDialog: ViewModifier {
    let appState: AppState

    func body(content: Content) -> some View {
        let action = appState.pendingRunInterruption
        content.confirmationDialog(
            RunInterruptionWording.title(operation: appState.activeOperation),
            isPresented: Binding(
                get: { appState.pendingRunInterruption != nil },
                set: { if !$0 { appState.dismissRunInterruption() } }
            ),
            titleVisibility: .visible,
            presenting: action
        ) { action in
            Button(RunInterruptionWording.confirmButton(action), role: .destructive) {
                appState.confirmRunInterruption()
            }
            Button("Cancel", role: .cancel) { appState.dismissRunInterruption() }
        } message: { action in
            Text(RunInterruptionWording.message(action, operation: appState.activeOperation))
        }
    }
}

/// Asks the window's `AppState` before its close button or ⌘W closes it. AppKit: SwiftUI has no close confirmation, so this view
/// finds its window and puts a delegate in front of SwiftUI's own that answers `windowShouldClose` and passes every other call on.
struct WindowCloseGuard: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> GuardView { GuardView(appState: appState) }
    func updateNSView(_ view: GuardView, context: Context) {}

    final class GuardView: NSView {
        private let appState: AppState
        private var proxy: CloseProxy?

        init(appState: AppState) {
            self.appState = appState
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used from a nib") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !(window.delegate is CloseProxy) else { return }
            let proxy = CloseProxy(original: window.delegate, appState: appState)
            self.proxy = proxy
            window.delegate = proxy
            appState.closeWindowWithoutAsking = { [weak window] in window?.close() }
        }
    }

    /// Answers `windowShouldClose` and forwards everything else to the delegate SwiftUI installed.
    final class CloseProxy: NSObject, NSWindowDelegate {
        private weak var original: NSWindowDelegate?
        private weak var appState: AppState?

        init(original: NSWindowDelegate?, appState: AppState) {
            self.original = original
            self.appState = appState
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if original?.windowShouldClose?(sender) == false { return false }
            return appState?.windowShouldClose() ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
}

/// Quit (⌘Q) asks the same question while a window runs an analysis (`RunGuard`). AppKit: SwiftUI has no quit confirmation.
final class Mac4DSTEMAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        RunGuard.shouldTerminate { sender.reply(toApplicationShouldTerminate: $0) }
    }
}

extension View {
    /// Hosts the "Stop <analysis>?" question for `appState`'s window, and asks it before the window closes.
    func runInterruptionDialog(_ appState: AppState) -> some View {
        modifier(RunInterruptionDialog(appState: appState))
            .background(WindowCloseGuard(appState: appState).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
