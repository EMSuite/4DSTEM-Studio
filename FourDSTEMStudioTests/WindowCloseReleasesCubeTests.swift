//
//  WindowCloseReleasesCubeTests.swift
//  #426: closing a dataset window releases the resident cube and drops the reader and array at once, even while something
//  (SwiftUI's closed-window state, in the app) still retains the window's `AppState`.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import FourDSTEMStudio

@MainActor
final class WindowCloseReleasesCubeTests: XCTestCase {

    /// The state is held strongly across the close, as SwiftUI held it in the Instruments pass (#291). Mutation it catches:
    /// `windowClosed` not releasing the cube or not dropping the array (red: still resident, or `fourD` still set).
    func testClosingTheWindowReleasesTheCubeWhileItsStateIsStillHeld() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let data = try XCTUnwrap(state.datasetSession.fourD, "the premise: the demo opened")
        await state.residency.request(.resident, on: data)
        _ = await state.residency.preload(data) { _ in }
        let heldBefore = await data.isResident
        XCTAssertTrue(heldBefore, "the premise: the demo cube is resident")

        await state.windowClosed().value

        let heldAfter = await data.isResident
        XCTAssertFalse(heldAfter, "the closed window still holds its resident cube")
        XCTAssertNil(state.datasetSession.fourD, "the closed window still holds its array")
        XCTAssertNil(state.datasetSession.reader, "the closed window still holds its reader (and the file mapping)")
        XCTAssertFalse(state.residency.isResident)
        XCTAssertEqual(state.residency.byteCount, 0)
    }
}
