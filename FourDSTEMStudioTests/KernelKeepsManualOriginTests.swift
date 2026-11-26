//
//  KernelKeepsManualOriginTests.swift
//  #364: Build Kernel measures a missing probe radius without replacing an origin set by hand.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import FourDSTEMStudio

@MainActor
final class KernelKeepsManualOriginTests: XCTestCase {

    /// Mutation it catches: `ensureProbeRadius` running Calibrate Origin for a hand-set origin (red: the provenance turns
    /// `.fitted` and the typed x moves).
    func testBuildKernelKeepsAHandSetOrigin() async throws {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        XCTAssertTrue(state.hasDataset, state.statusText)
        state.calibrationSession.calibration.probeRadius = nil
        state.setManualOrigin(x: 33.5, y: 26)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual)

        state.navigation.analysisMode = .disks
        await state.generateProbeKernel()

        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual, state.statusText)
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginX, 33.5)
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginY, 26)
        let radius = try XCTUnwrap(state.calibrationSession.calibration.probeRadius, state.statusText)
        XCTAssertGreaterThan(radius, 0)
        XCTAssertEqual(state.calibrationSession.provenance.probe, .measuredInApp)
        XCTAssertNotNil(state.probeKernel, state.statusText)
    }
}
