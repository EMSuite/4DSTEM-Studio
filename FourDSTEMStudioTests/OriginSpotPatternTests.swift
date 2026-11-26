import XCTest
import DSTEMCore
@testable import FourDSTEMStudio

/// #511: on a spot pattern whose disks are as bright as the beam, the centre-of-mass origin follows the brightest disk, so it
/// scatters by a disk spacing. py4DSTEM's `get_origin` (0.14.18: the argmax of the Gaussian-filtered pattern, then the centre
/// of mass inside 1.2 r) does the same: on a synthetic 24 × 24 scan with two disks as bright as the beam, 73 % of its
/// positions were a whole disk spacing off and its plane fit left 8.2 px RMS. The method stays; what changes is that such an
/// origin reads "Flagged" (the row, the overlay key, the door's `calibration`) and never "Measured", and that the spot
/// pattern's route (Detect All Disks, then Origin from Bragg Peaks) is one action and one door call.
///
/// The cube: an 8 × 8 scan of a 66 × 66 detector, the direct beam at (33, 33) and two disks 16 px either side of it, all of
/// radius 2.5 px. At every position one of the two side disks is brighter than the beam, the left one on a checkerboard and
/// the right one on the other squares, so the brightest disk hops by 32 px between neighbours and no plane can follow it.
private actor HoppingSpotPatternSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(filePath: "/synthetic/hopping-spots.h5", datasetPath: "/data",
                                              shape: [8, 8, 66, 66], dtypeDescription: "float32", chunkShape: nil)
    static let beam = (x: 33.0, y: 33.0)
    private let cube: [Float] = {
        var values = [Float]()
        for ry in 0..<8 {
            for rx in 0..<8 {
                var dp = [Float](repeating: 30, count: 66 * 66)
                let leftBright = (rx + ry) % 2 == 0
                ProbeRadiusSeveralDisksTests.drawDisk(into: &dp, width: 66, cx: beam.x, cy: beam.y, radius: 2.5, value: 255)
                ProbeRadiusSeveralDisksTests.drawDisk(into: &dp, width: 66, cx: beam.x - 16, cy: beam.y, radius: 2.5,
                                                      value: leftBright ? 300 : 240)
                ProbeRadiusSeveralDisksTests.drawDisk(into: &dp, width: 66, cx: beam.x + 16, cy: beam.y, radius: 2.5,
                                                      value: leftBright ? 240 : 300)
                values += dp
            }
        }
        return values
    }()

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { view.pattern(fromFullCube: cube, ry: ry, rx: rx) }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { view.scanRow(fromFullCube: cube, ry: ry) }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile { view.scanTile(fromFullCube: cube, yRange: yRange) }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

@MainActor
final class OriginSpotPatternTests: XCTestCase {
    private func originRow(_ state: AppState) throws -> CalibrationReadinessItem {
        try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .originProbe })
    }

    private func doorOriginItem(_ state: AppState) throws -> [String: Any] {
        let items = try XCTUnwrap(state.agentCalibration["items"] as? [[String: Any]])
        return try XCTUnwrap(items.first { $0["item"] as? String == CalibrationReadinessKind.originProbe.rawValue })
    }

    private func flagged(_ state: AppState) -> Bool {
        CalibrationReadinessReport.originIsFlagged(calibration: state.calibrationSession.calibration,
                                                   provenance: state.calibrationSession.provenance)
    }

    /// Mutation: the row reads the provenance's "Measured" over a scattered centre of mass, or the door drops the flag - red.
    func testAScatteredCentreOfMassOnASpotPatternReadsFlaggedEverywhere() async throws {
        let source = HoppingSpotPatternSource()
        let state = AppState()
        await state.activate(descriptor: try await source.discoverPrimaryDataset(), reader: source, runInitialAnalysis: false)
        await state.calibrateOrigin()
        let rms = try XCTUnwrap(state.calibrationSession.calibration.origin?.rmsResidual)
        XCTAssertGreaterThan(rms, 4, "fixture: the brightest disk must hop, so the centre of mass scatters (\(rms) px)")
        XCTAssertTrue(flagged(state))

        let row = try originRow(state)
        XCTAssertTrue(row.detail.hasPrefix("Origin: Flagged"), row.detail)
        XCTAssertFalse(row.detail.contains("Origin: Measured"), row.detail)
        XCTAssertNotNil(row.flag)
        XCTAssertTrue(CalibrationReadinessRow.isWarning(row, canRestoreFittedOrigin: false), "a flagged origin row is orange")

        let door = try doorOriginItem(state)
        XCTAssertEqual(door["flag"] as? String, row.flag)
        XCTAssertTrue((door["detail"] as? String)?.hasPrefix("Origin: Flagged") == true, "\(door)")
    }

    /// The one-step route: Detect All Disks (none exist yet), then the origin from the Bragg peaks, which follows the beam.
    /// Mutation: the step stops after the detection, or refuses without a detection as it did - red.
    func testOriginFromBraggPeaksInOneStepDetectsTheDisksAndFollowsTheBeam() async throws {
        let source = HoppingSpotPatternSource()
        let state = AppState()
        await state.activate(descriptor: try await source.discoverPrimaryDataset(), reader: source, runInitialAnalysis: false)
        await state.calibrateOrigin()
        XCTAssertTrue(flagged(state), "fixture")
        await state.useProbeRadius(2.5)   // several disks as bright as the beam: the radius is typed, as the row asks
        XCTAssertNil(state.resultPresentation.braggVectors, "fixture: no detection before the step")

        await state.originFromBraggPeaksInOneStep()
        XCTAssertTrue(state.statusText.hasPrefix("Origin from Bragg peaks ✓"), state.statusText)
        XCTAssertNotNil(state.resultPresentation.braggVectors, "the step ran Detect All Disks")
        XCTAssertFalse(flagged(state))
        let row = try originRow(state)
        XCTAssertNil(row.flag)
        XCTAssertFalse(row.detail.contains("Flagged"), row.detail)
        let mean = try XCTUnwrap(state.calibrationSession.calibration.meanOrigin)
        XCTAssertEqual(Double(mean.x), HoppingSpotPatternSource.beam.x, accuracy: 0.5)
        XCTAssertEqual(Double(mean.y), HoppingSpotPatternSource.beam.y, accuracy: 0.5)
        XCTAssertLessThan(try XCTUnwrap(state.calibrationSession.calibration.origin?.rmsResidual), 0.5)
    }

    /// "Mixed" says what is mixed (#511: the door read "Mixed" with ready true). The demo's origin measured, its probe typed.
    func testAMixedOriginRowNamesEachSource() async throws {
        let demo = AppState()
        await demo.openDemoFixture(calibrated: false)
        await demo.calibrateOrigin()
        await demo.useProbeRadius(4)
        let row = try originRow(demo)
        XCTAssertEqual(row.status, .ready(.mixed), "fixture: \(row.status)")
        XCTAssertEqual(row.stateText, "Mixed: origin Measured, probe Manual")
        XCTAssertEqual(try doorOriginItem(demo)["state"] as? String, "Mixed: origin Measured, probe Manual")
        XCTAssertNil(row.flag, "the demo's single bright disk is not a spot pattern")
    }
}
