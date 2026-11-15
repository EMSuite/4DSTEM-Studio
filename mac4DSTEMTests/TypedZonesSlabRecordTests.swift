import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// mac4DSTEM#408: in typed-zones mode the excitation slab looked ignored. The kit applies each phase's slab (or the global
/// one), but on an exact zone axis it only admits higher Laue zones, which the excitation width weights down, so 0.06 and
/// 0.3 Å⁻¹ gave the same map; and the run record (and the door's `excitation_slabs`) said nothing about the slab it used.
/// A typed run now records each candidate with its slab, as a structures run does.
@MainActor
final class TypedZonesSlabRecordTests: XCTestCase {

    /// Mutation: `excitationSlabs` left out of the typed run's record -> an empty list -> red.
    func testATypedZonesRunRecordsTheSlabOfEachCandidate() async throws {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        let state = AppState()
        await state.openDemoFixture(specification: spec)
        let d = try XCTUnwrap(state.descriptor, state.statusText)
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        let beam = state.calibrationSession.calibration.referenceOrigin(detectorQX: d.qx, detectorQY: d.qy).point
        let count = d.rx * d.ry
        state.calibrationSession.calibration.origin = OriginMaps(
            width: d.rx, height: d.ry, measuredX: Array(repeating: beam.x, count: count),
            measuredY: Array(repeating: beam.y, count: count),
            fittedX: Array(repeating: beam.x, count: count), fittedY: Array(repeating: beam.y, count: count))
        state.calibrationSession.calibration.originProvenance = .fitted
        state.aperture.centerX = beam.x
        state.aperture.centerY = beam.y
        state.phaseMapping.applyAlMgSiPreset(precipitate: try XCTUnwrap(CrystalModelLibrary.model(id: "mg_hcp")))

        let candidates = state.phaseMapping.phases.filter { !$0.isMatrix }
        let own = try XCTUnwrap(candidates.first)
        XCTAssertTrue(state.phaseMapping.updatePhase(id: own.id) { $0.excitationSlabInvAngstrom = 0.3 })

        state.navigation.analysisMode = .phaseMapping
        _ = await state.runPhaseMapping()
        XCTAssertNotNil(state.phaseMapping.map, state.statusText)
        let slabs = try XCTUnwrap(state.phaseMapping.lastRun?.excitationSlabs)
        XCTAssertEqual(slabs.count, candidates.count, "one entry per candidate phase: \(slabs)")
        XCTAssertEqual(slabs.filter { $0.hasSuffix(": 0.3") }.count, 1, "the phase's own slab: \(slabs)")
        let global = String(format: "%.3g", state.phaseMapping.reference.excitationSlabInvAngstrom)
        XCTAssertEqual(slabs.filter { $0.hasSuffix(": \(global)") }.count, candidates.count - 1,
                       "the others with the library's slab: \(slabs)")
    }
}
