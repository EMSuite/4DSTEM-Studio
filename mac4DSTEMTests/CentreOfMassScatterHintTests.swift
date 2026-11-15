import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// mac4DSTEM#324: on Paul's GMS cubes the centre-of-mass origin (py4DSTEM's `get_origin`, which the app runs as CuboKit's
/// port) scattered 1.4 to 2.8 px on 090, 095 and 087 where the origin from the Bragg peaks read 0.17 to 0.3 px, and the app
/// said nothing: its one limit is the probe radius (2.6 to 6.9 px there). Over 1 px the status line and the Origin & probe
/// row now point to Origin from Bragg Peaks; a tight fit says nothing new.
///
/// The cube: an 8 × 8 scan of a 48 × 48 detector, one disk of radius 4 px, its centre jittered per position by a fixed
/// pseudo-random offset of up to ±3 px (a plane cannot follow it), or not at all.
private actor JitteredBeamSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(filePath: "/synthetic/jittered-beam.h5", datasetPath: "/data",
                                              shape: [8, 8, 48, 48], dtypeDescription: "float32", chunkShape: nil)
    private let cube: [Float]

    init(jitter: Double) {
        var values = [Float]()
        var seed: UInt64 = 0x324
        func next() -> Double {   // a fixed LCG, so the cube is the same on every run
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31) * 2 - 1
        }
        for _ in 0..<64 {
            var dp = [Float](repeating: 1, count: 48 * 48)
            let cx = 23.5 + jitter * next(), cy = 23.5 + jitter * next()
            for y in 0..<48 { for x in 0..<48 where hypot(Double(x) - cx, Double(y) - cy) <= 4 { dp[y * 48 + x] = 100 } }
            values += dp
        }
        cube = values
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { view.pattern(fromFullCube: cube, ry: ry, rx: rx) }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { view.scanRow(fromFullCube: cube, ry: ry) }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile { view.scanTile(fromFullCube: cube, yRange: yRange) }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

@MainActor
final class CentreOfMassScatterHintTests: XCTestCase {
    private let hint = "Centre of mass scattered: after Detect All Disks use Origin from Bragg Peaks"

    private func row(_ state: AppState) -> String {
        state.calibrationSession.readiness.items.first { $0.kind == .originProbe }?.detail ?? "no Origin & probe row"
    }

    /// Mutation: the scatter test dropped from `calibrateOrigin` -> no hint at 1.7 px -> red.
    func testAScatteredCentreOfMassPointsToTheOriginFromBraggPeaks() async throws {
        let source = JitteredBeamSource(jitter: 3)
        let state = AppState()
        await state.activate(descriptor: try await source.discoverPrimaryDataset(), reader: source, runInitialAnalysis: false)
        await state.calibrateOrigin()
        let rms = try XCTUnwrap(state.calibrationSession.calibration.origin?.rmsResidual)
        XCTAssertGreaterThan(rms, Calibration.centreOfMassScatterHintPixels, "fixture: the jitter must scatter the fit")
        XCTAssertTrue(state.calibrationSession.calibration.originResidualIsAcceptable,
                      "fixture: under the probe radius, where the app said nothing before (\(rms) px)")
        XCTAssertTrue(state.calibrationSession.provenance.suggestsOriginFromBraggPeaks)
        XCTAssertTrue(row(state).contains(hint), row(state))
        XCTAssertFalse(row(state).contains("Spot pattern"), "one disk is not a spot pattern: \(row(state))")
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("scattered: try Origin from Bragg Peaks") },
                      "the status line does not say it: \(state.statusText)")
    }

    func testATightCentreOfMassSaysNothingNew() async throws {
        let source = JitteredBeamSource(jitter: 0)
        let state = AppState()
        await state.activate(descriptor: try await source.discoverPrimaryDataset(), reader: source, runInitialAnalysis: false)
        await state.calibrateOrigin()
        XCTAssertLessThan(try XCTUnwrap(state.calibrationSession.calibration.origin?.rmsResidual), 0.1)
        XCTAssertFalse(state.calibrationSession.provenance.suggestsOriginFromBraggPeaks)
        XCTAssertFalse(row(state).contains("Origin from Bragg Peaks"), row(state))
    }
}
