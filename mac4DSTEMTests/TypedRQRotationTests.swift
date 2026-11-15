//
//  TypedRQRotationTests.swift
//  #275: the R–Q rotation and transpose typed by hand, in py4DSTEM's convention (`QR_rotation` in degrees, `QR_flip`), as
//  py4DSTEM's calibration lets a person set them. The typed angle is the one the screen, the door and the files show; the app
//  stores its own (negated) angle internally (`RQRotationConvention`, ADR 040). Each test names the mutation it was red on.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class TypedRQRotationTests: XCTestCase {

    /// py4DSTEM's 15° with QR_flip (what py4DSTEM's DPC gives on downsample_Si_SiGe_exp.h5) is stored as the app's −15° with
    /// the transpose, shows as 15.0° and is marked typed. Mutation: storing the typed angle unnegated - red (the screen and the
    /// door would read −15°, and DPC, strain and ACOM would rotate the wrong way).
    func testATypedRotationIsPy4DSTEMsSignAndCarriesItsTranspose() throws {
        let session = CalibrationSession()
        XCTAssertNil(session.applyManualRotation(py4DSTEMDegrees: 15, transpose: true))
        let stored = try XCTUnwrap(session.calibration.rotationRad)
        XCTAssertEqual(Double(stored), -15 * .pi / 180, accuracy: 1e-6)
        XCTAssertEqual(RQRotationConvention.displayDegrees(fromApp: stored), 15, accuracy: 1e-4)
        XCTAssertEqual(session.calibration.transposeQR, true)
        XCTAssertEqual(session.provenance.rotation, .manual)

        // The transpose is written with the angle every time: typing an angle without the flip clears a measured one.
        XCTAssertNil(session.applyManualRotation(py4DSTEMDegrees: -80, transpose: false))
        XCTAssertEqual(session.calibration.transposeQR, false)
        XCTAssertEqual(RQRotationConvention.displayDegrees(fromApp: try XCTUnwrap(session.calibration.rotationRad)), -80, accuracy: 1e-4)
    }

    /// An angle outside a half turn each way is the same rotation: it is stored in (−180°, 180°], as Flip 180° keeps it.
    /// Mutation: no wrap - red.
    func testATypedRotationWrapsToOneTurn() throws {
        let session = CalibrationSession()
        XCTAssertNil(session.applyManualRotation(py4DSTEMDegrees: 190, transpose: false))
        XCTAssertEqual(RQRotationConvention.displayDegrees(fromApp: try XCTUnwrap(session.calibration.rotationRad)), -170, accuracy: 1e-4)
        XCTAssertNil(session.applyManualRotation(py4DSTEMDegrees: -540, transpose: false))
        XCTAssertEqual(abs(RQRotationConvention.displayDegrees(fromApp: try XCTUnwrap(session.calibration.rotationRad))), 180, accuracy: 1e-4)
    }

    /// A value that is not an angle writes nothing: an earlier rotation stands. Mutation: the finiteness guard removed - red.
    func testANonFiniteAngleIsRefusedAndTheEarlierRotationStands() throws {
        let session = CalibrationSession()
        XCTAssertNil(session.applyManualRotation(py4DSTEMDegrees: 12, transpose: true))
        XCTAssertNotNil(session.applyManualRotation(py4DSTEMDegrees: .nan, transpose: false))
        XCTAssertEqual(RQRotationConvention.displayDegrees(fromApp: try XCTUnwrap(session.calibration.rotationRad)), 12, accuracy: 1e-4)
        XCTAssertEqual(session.calibration.transposeQR, true)
    }

    /// The window's entry point writes the rotation and says so on the status line, in py4DSTEM's sign with the transpose.
    /// Mutation: `AppState.applyManualRotation` writing the session without the re-derivation and its line - red.
    func testTheWindowSaysWhatWasTyped() throws {
        let state = AppState()
        state.applyManualRotation(py4DSTEMDegrees: 15, transpose: true)
        XCTAssertEqual(state.calibrationSession.provenance.rotation, .manual)
        XCTAssertTrue(state.statusText.contains("15.0°"), state.statusText)
        XCTAssertTrue(state.statusText.contains("transposed"), state.statusText)
    }
}
