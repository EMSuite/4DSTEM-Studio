//
//  OneLoadGuardTests.swift
//  mac4DSTEM#303: one open at a time, claimed synchronously before the open's first await. The guard used to read
//  `datasetSession.isLoading`, which the open sets only after its spectrum-image check (two hops off the main actor), so a drop
//  plus ⌘O, a double Finder open or an agent's open_file all passed it together, although the bundled HDF5 is not thread-safe.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class OneLoadGuardTests: XCTestCase {
    private let refusal = "Already opening a dataset — wait for that one to finish, or cancel it."

    private func refusals(_ state: AppState) -> Int {
        state.activityLog.messages.filter { $0.hasSuffix(refusal) }.count
    }

    /// Two opens started back to back: the second finds the first's claim, though the first has not begun loading yet.
    /// Mutation: the claim back on `isLoading` alone - red (no refusal; both opens run).
    func testTwoOpensStartedTogetherLoadOnce() async {
        let state = AppState()
        let url = URL(fileURLWithPath: "/nonexistent/one-load-guard.h5")
        let first = Task { await state.openFileAsync(url: url) }
        let second = Task { await state.openFileAsync(url: url) }   // runs while the first awaits its spectrum-image check
        await first.value
        await second.value
        XCTAssertEqual(refusals(state), 1, "the second open was not refused: \(state.activityLog.messages.suffix(6))")
        XCTAssertTrue(state.claimOpen(), "the claim is released when the open returns")
        state.releaseOpenClaim()
    }

    /// `openFile` claims before its Task starts, so a second `openFile` in the same turn is refused at once.
    func testASecondOpenFileInTheSameTurnIsRefusedAtOnce() async {
        let state = AppState()
        state.openFile(url: URL(fileURLWithPath: "/nonexistent/a.h5"))
        state.openFile(url: URL(fileURLWithPath: "/nonexistent/b.h5"))
        XCTAssertEqual(state.statusText, refusal)
        XCTAssertFalse(state.claimOpen(), "the first open still holds the claim")
    }
}
