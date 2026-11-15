//
//  RunInterruptionTests.swift
//  #313: closing the window, opening another file or quitting while an analysis runs asks first; nothing is asked when no run is
//  in flight. Each test names the mutation it was broken on.
//

import AppKit
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class RunInterruptionTests: XCTestCase {

    private func running(_ name: String = "Phase mapping") -> (AppState, AnalysisCancellationToken) {
        let state = AppState()
        let token = state.beginCancellableOperation(name, status: "Running \(name)…")
        XCTAssertTrue(state.analysisIsRunning, "precondition: an analysis runs")
        return (state, token)
    }

    /// Mutation: `windowShouldClose` returning true (the close stops the run unasked, as before #313) - red.
    func testClosingDuringARunAsksAndKeepsTheRunUntilConfirmed() {
        let (state, token) = running()
        var closed = 0
        state.closeWindowWithoutAsking = { closed += 1 }
        XCTAssertFalse(state.windowShouldClose(), "the window closed without asking")
        XCTAssertEqual(state.pendingRunInterruption, RunInterruption.close)
        XCTAssertFalse(token.isCancelled, "asking must not stop the run")
        XCTAssertTrue(state.isBusy)

        state.confirmRunInterruption()
        XCTAssertEqual(closed, 1)
        XCTAssertFalse(state.isBusy, "Stop and Close stops the run")
        XCTAssertNil(state.pendingRunInterruption)
    }

    /// Cancel keeps the window and the run. Mutation: dismiss stopping the run - red.
    func testCancellingTheQuestionKeepsTheRun() {
        let (state, token) = running()
        var closed = 0
        state.closeWindowWithoutAsking = { closed += 1 }
        _ = state.windowShouldClose()
        state.dismissRunInterruption()
        XCTAssertEqual(closed, 0)
        XCTAssertFalse(token.isCancelled)
        XCTAssertTrue(state.isBusy)
        XCTAssertNil(state.pendingRunInterruption)
    }

    /// Nothing runs: the window closes at once and nothing is asked. Mutation: always asking - red.
    func testNothingIsAskedWhenNoRunIsInFlight() {
        let state = AppState()
        XCTAssertTrue(state.windowShouldClose())
        XCTAssertNil(state.pendingRunInterruption)
        XCTAssertFalse(state.askBeforeInterruptingRun(.open(URL(fileURLWithPath: "/nonexistent/x.h5"), configure: false)))
    }

    /// Opening another file during a run asks first, naming the file; the run goes on until the answer. Mutation: the open's
    /// guard removed - red (no question; the open would replace the dataset under the run).
    func testOpeningAnotherFileDuringARunAsksFirst() {
        let (state, token) = running("Orientation mapping")
        let url = URL(fileURLWithPath: "/nonexistent/next.h5")
        state.openFile(url: url)
        XCTAssertEqual(state.pendingRunInterruption, RunInterruption.open(url, configure: false))
        XCTAssertFalse(token.isCancelled)
        XCTAssertEqual(RunInterruptionWording.message(.open(url, configure: false), operation: state.activeOperation),
                       "Orientation mapping is still running. Opening next.h5 stops it, and what it has computed so far is lost.")
        state.dismissRunInterruption()
        XCTAssertTrue(state.isBusy)
    }

    /// Quit asks the window that runs, and quits on its answer. Mutation: `shouldTerminate` answering `.terminateNow` - red.
    func testQuittingDuringARunAsksAndQuitsOnTheAnswer() {
        let (state, _) = running()
        RunGuard.enroll(state)
        defer { RunGuard.withdraw(state) }
        var replies: [Bool] = []
        XCTAssertEqual(RunGuard.shouldTerminate { replies.append($0) }, .terminateLater)
        XCTAssertEqual(state.pendingRunInterruption, RunInterruption.quit)
        state.dismissRunInterruption()
        XCTAssertEqual(replies, [false], "Cancel keeps the app")
        XCTAssertTrue(state.isBusy)

        XCTAssertEqual(RunGuard.shouldTerminate { replies.append($0) }, .terminateLater)
        state.confirmRunInterruption()
        XCTAssertEqual(replies, [false, true], "Stop and Quit quits")
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(RunGuard.shouldTerminate { replies.append($0) }, .terminateNow, "nothing runs: quit at once")
    }

    /// A session-file save is not an analysis: closing or quitting during it is refused with the save's own sentence (as an open
    /// is), never asked as "Stop …?" and never cancelling the write. Mutation: the save check removed - red (the question, or a
    /// close that cancels the save).
    func testClosingOrQuittingDuringASessionSaveWaitsForIt() throws {
        let saveName = try XCTUnwrap(SessionSidecarLocator.saveOperationNames.first)
        let state = AppState()
        let token = state.beginCancellableOperation(saveName, status: "Saving…")
        var closed = 0
        state.closeWindowWithoutAsking = { closed += 1 }
        XCTAssertFalse(state.windowShouldClose())
        XCTAssertNil(state.pendingRunInterruption, "a save is not asked about as an analysis")
        XCTAssertTrue(state.statusText.hasPrefix("Still saving the session file"), state.statusText)
        XCTAssertFalse(token.isCancelled)
        XCTAssertEqual(closed, 0)

        RunGuard.enroll(state)
        defer { RunGuard.withdraw(state) }
        var replies: [Bool] = []
        XCTAssertEqual(RunGuard.shouldTerminate { replies.append($0) }, .terminateCancel)
        XCTAssertTrue(replies.isEmpty)
        XCTAssertFalse(token.isCancelled)
    }

    func testTheButtonsNameWhatTheyDo() {
        XCTAssertEqual(RunInterruptionWording.confirmButton(.close), "Stop and Close")
        XCTAssertEqual(RunInterruptionWording.confirmButton(.quit), "Stop and Quit")
        XCTAssertEqual(RunInterruptionWording.title(operation: "Phase mapping"), "Stop Phase mapping?")
    }
}
