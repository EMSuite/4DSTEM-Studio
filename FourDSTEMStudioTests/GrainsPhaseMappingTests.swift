//
//  GrainsPhaseMappingTests.swift
//  mac4DSTEM#252: "Grains and phases (no matrix)". The method choice and its refusals; the run on a planted two-phase
//  polycrystal (aluminium and magnesium grains, every pattern the zero-order spots of its grain's zone at its in-plane angle,
//  written out here and not taken from the libraries under test) mapped from the two structures alone; the threshold read from
//  the held run; the colours of a map without a matrix.
//

import XCTest
import simd
import ImageIO
import DSTEMCore
import DSTEMSession
import DiffractoCore
import DiffractoOrientation
@testable import FourDSTEMStudio

@MainActor
final class GrainsPhaseMappingTests: XCTestCase {
    private static let q = 0.012, reach = 0.75
    private static let origin = 63.5

    private struct Grain { let phase: Int; let zone: SIMD3<Double>; let inPlaneDeg: Double }

    /// The zero-order pattern of a zone (Cartesian, the crystal's frame) at an in-plane angle, in detector pixels, direct beam
    /// included (the run leaves it out).
    private static func pattern(_ zone: SIMD3<Double>, inPlaneDeg: Double, _ crystal: CrystalStructure) throws -> [SIMD2<Double>] {
        let n = simd_normalize(zone)
        let basis = ZoneAxisFrame.detectorBasis(zoneAxis: n)
        let c = cos(inPlaneDeg * .pi / 180), s = sin(inPlaneDeg * .pi / 180)
        var peaks = [SIMD2(origin, origin)]
        for k in try crystal.kinematicReflections(kMax: reach, retainingAll: false).kept {
            let g = k.reflection.g
            guard abs(simd_dot(g, n)) < 1e-6, simd_length(g) < reach else { continue }
            let x = simd_dot(g, basis.columns.0), y = simd_dot(g, basis.columns.1)
            peaks.append(SIMD2(origin + (c * x - s * y) / q, origin + (s * x + c * y) / q))
        }
        return peaks
    }

    /// Six grains on a 6 x 4 scan, four positions each (Al on [001], [011], [111]; Mg on [0001], [2-1-10], [01-10]), and two
    /// positions with no peak but the direct beam. Every position with spots takes its planted phase, sure at ASTAR's 15, with
    /// the winner's orientation's beam within 3 degrees of the planted zone; the empty positions are "no peaks". The field the
    /// orientation map draws holds the same phases and a reliability at every position with a winner.
    /// Mutations: the winner taken as the lowest score (every phase wrong); the orientation taken from the runner-up's field (the
    /// beam test fails); no-peak positions read as not indexed.
    func testAPlantedTwoPhasePolycrystalIsMappedFromItsTwoStructures() throws {
        let crystals = [CrystalPresets.aluminum, CrystalPresets.magnesium]
        let grains = [
            Grain(phase: 0, zone: SIMD3(0, 0, 1), inPlaneDeg: 12), Grain(phase: 1, zone: SIMD3(0, 0, 1), inPlaneDeg: 20),
            Grain(phase: 0, zone: SIMD3(0, 1, 1), inPlaneDeg: 40), Grain(phase: 1, zone: SIMD3(1, 0, 0), inPlaneDeg: 5),
            Grain(phase: 0, zone: SIMD3(1, 1, 1), inPlaneDeg: 70), Grain(phase: 1, zone: SIMD3(0, 1, 0), inPlaneDeg: 33),
        ]
        let width = 6, height = 4, empty: Set = [0, 23]
        func grain(_ i: Int) -> Grain { grains[((i / width) / 2) * 3 + (i % width) / 2] }
        let scan = try (0..<width * height).map { i -> [SIMD2<Double>] in
            if empty.contains(i) { return [SIMD2(Self.origin, Self.origin)] }
            let g = grain(i)
            return try Self.pattern(g.zone, inPlaneDeg: g.inPlaneDeg, crystals[g.phase])
        }
        let run = try XCTUnwrap(try GrainsPhaseRun.run(
            scan: scan, scanWidth: width, scanHeight: height, phases: [("Al", crystals[0]), ("Mg", crystals[1])],
            reachInvAngstrom: Self.reach, maximumVectorInvAngstrom: Self.reach, directBeamRadiusInvAngstrom: 0.15,
            originX: Float(Self.origin), originY: Float(Self.origin), invAngstromPerPixel: Self.q))
        let threshold = GrainsPhaseRun.defaultReliableAbove
        XCTAssertEqual(threshold, 15)
        let map = run.phaseMap(reliableAbove: threshold)
        XCTAssertEqual(map.matrixPhaseIndex, -1)
        XCTAssertEqual(map.count(of: .matrix), 0)
        XCTAssertEqual(map.count(of: .noData), 2)
        XCTAssertEqual(map.phaseCounts, [11, 11])
        XCTAssertEqual(run.counts(reliableAbove: threshold).perPhase, [11, 11])
        XCTAssertEqual(run.counts(reliableAbove: threshold).unsure, 0)
        let field = run.orientationField(reliableAbove: threshold)
        for i in 0..<width * height {
            if empty.contains(i) {
                XCTAssertEqual(map.results[i].verdict, .noData, "position \(i)")
                XCTAssertEqual(field.phaseIndex[i], -1)
                XCTAssertTrue(field.reliability?[i].isNaN ?? false)
                continue
            }
            let g = grain(i)
            XCTAssertEqual(map.results[i].verdict, .indexed, "position \(i)")
            XCTAssertEqual(Int(map.results[i].phaseIndex), g.phase, "position \(i)")
            XCTAssertEqual(field.phaseIndex[i], g.phase)
            let reliability = try XCTUnwrap(field.reliability?[i])
            XCTAssertGreaterThanOrEqual(reliability, threshold, "position \(i)")
            // The beam (the orientation's third column) within 3 degrees of the planted zone, up to the phase's symmetry.
            let beam = simd_normalize(try XCTUnwrap(field.orientation[i]).columns.2)
            let planted = simd_normalize(g.zone)
            let angle = field.symmetries[g.phase].operators
                .map { acos(min(1, abs(simd_dot($0 * planted, beam)))) * 180 / .pi }.min() ?? 180
            XCTAssertLessThan(angle, 3, "position \(i): beam \(angle) degrees from the planted zone")
        }
        // The pictures for a reader, when asked for (`MACEM_PICTURES` names a folder): the map, the reliability, each IPF-Z.
        if let folder = ProcessInfo.processInfo.environment["MACEM_PICTURES"] {
            let url = URL(fileURLWithPath: folder)
            Self.write(PhaseMapPresentation.image(map), to: url.appendingPathComponent("grains-phase-map.png"))
            if let r = field.reliabilityImage() {
                let grey = r.pixels.flatMap { v -> [UInt8] in
                    guard v.isFinite else { return [0, 0, 0, 0] }
                    let g = UInt8(min(255, max(0, Double(v) / 100 * 255)).rounded())
                    return [g, g, g, 255]
                }
                Self.write(RGBAImage(width: width, height: height, rgba: grey), to: url.appendingPathComponent("grains-reliability.png"))
            }
            for p in 0..<2 {
                Self.write(field.ipfZImage(phase: p), to: url.appendingPathComponent("grains-ipf-\(field.phaseNames[p]).png"))
            }
        }
        let line = run.evidenceLine(at: 7, reliableAbove: threshold)
        XCTAssertTrue(line.hasPrefix(grain(7).phase == 0 ? "Al — correlation" : "Mg — correlation"), line)
        XCTAssertEqual(run.evidenceLine(at: 0, reliableAbove: threshold), "No peaks at this position.")
    }

    /// An RGBA picture written as a PNG, each position a 40-pixel square.
    private static func write(_ image: RGBAImage, to url: URL, scale: Int = 40) {
        let w = image.width * scale, h = image.height * scale
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let s = ((y / scale) * image.width + x / scale) * 4, d = (y * w + x) * 4
            out[d..<d + 4] = image.rgba[s..<s + 4]
        } }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }

    /// The threshold is a reading of the held run: above every position's reliability nothing is sure and every position with
    /// spots is not indexed (the field keeps the reliabilities, so the reliability map still shows them); at 0 every winner is
    /// drawn. Mutation: the threshold compared with `>` to the score instead of the reliability.
    func testTheThresholdIsReadFromTheHeldRun() {
        func m(_ score: Float) -> OrientationResult {
            var r = OrientationResult.empty
            r.templateIndex = 0; r.score = score
            return r
        }
        let cubic = CrystalOrientationSymmetry(laueClass: .mThreeBarM)
        // Position 0: phase 1 wins 0.8 to 0.6 (reliability 25); position 1: phase 0 wins 0.5 to 0.45 (10); position 2: no peaks.
        let a = MatrixOrientationField(width: 3, height: 1, results: [m(0.6), m(0.5), .empty],
                                       orientations: [matrix_identity_double3x3, matrix_identity_double3x3, nil])
        let b = MatrixOrientationField(width: 3, height: 1, results: [m(0.8), m(0.45), .empty],
                                       orientations: [matrix_identity_double3x3, matrix_identity_double3x3, nil])
        guard let run = GrainsPhaseRun.make(phaseNames: ["A", "B"], symmetries: [cubic, cubic], fields: [a, b],
                                            usablePeakCounts: [5, 5, 0]) else { return XCTFail("the fields fit one scan") }
        XCTAssertEqual(run.phaseMap(reliableAbove: 15).results.map(\.verdict), [.indexed, .notIndexed, .noData])
        XCTAssertEqual(run.phaseMap(reliableAbove: 15).results[0].phaseIndex, 1)
        XCTAssertEqual(run.phaseMap(reliableAbove: 0).results.map(\.verdict), [.indexed, .indexed, .noData])
        XCTAssertEqual(run.phaseMap(reliableAbove: 30).results.map(\.verdict), [.notIndexed, .notIndexed, .noData])
        XCTAssertEqual(run.counts(reliableAbove: 15).perPhase, [0, 1])
        XCTAssertEqual(run.counts(reliableAbove: 15).unsure, 1)
        let field = run.orientationField(reliableAbove: 30)
        XCTAssertEqual(field.phaseIndex, [-1, -1, -1])
        XCTAssertEqual(field.reliability?[0] ?? 0, 25, accuracy: 1e-4)
        XCTAssertEqual(field.reliability?[1] ?? 0, 10, accuracy: 1e-4)
        XCTAssertEqual(field.reliabilityValidity(), [true, true, false])
        XCTAssertTrue(run.evidenceLine(at: 1, reliableAbove: 15).hasSuffix("below 15: not indexed."))
        XCTAssertNil(GrainsPhaseRun.make(phaseNames: ["A"], symmetries: [cubic], fields: [a, b], usablePeakCounts: [5, 5, 0]))
    }

    /// A Grains and phases map offers no claimed-disks overlay (it said "Reference library not kept for this map — run
    /// again" right after a fresh run); a matrix map still does. Mutation: `offersClaims` ignores the source - red.
    func testAGrainsMapOffersNoClaimsOverlay() {
        func m(_ score: Float) -> OrientationResult {
            var r = OrientationResult.empty
            r.templateIndex = 0; r.score = score
            return r
        }
        let cubic = CrystalOrientationSymmetry(laueClass: .mThreeBarM)
        let a = MatrixOrientationField(width: 1, height: 1, results: [m(0.6)], orientations: [matrix_identity_double3x3])
        let b = MatrixOrientationField(width: 1, height: 1, results: [m(0.8)], orientations: [matrix_identity_double3x3])
        guard let run = GrainsPhaseRun.make(phaseNames: ["A", "B"], symmetries: [cubic, cubic], fields: [a, b],
                                            usablePeakCounts: [5]) else { return XCTFail("the fields fit one scan") }
        func record(_ source: PhaseOrientationSource) -> PhaseMappingProduct.RunRecord {
            PhaseMappingProduct.RunRecord(
                phaseSignature: "fixture", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(),
                libraryEntryCount: 0, matrixEntryIndex: -1, matrixInPlaneDegrees: .nan, worstChanceMatchPercent: 0,
                invAngstromPerPixel: 0.01, qScaleIsPhysical: false, peakCount: 0,
                calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0)),
                orientationSource: source)
        }
        let product = PhaseMappingProduct()
        XCTAssertFalse(product.offersClaims, "no map")
        product.publish(grains: run, ranWith: record(.grains))
        XCTAssertFalse(product.offersClaims)
        product.publish(run.phaseMap(reliableAbove: 15), ranWith: record(.structures))
        XCTAssertTrue(product.offersClaims)
    }

    /// A grains run's provenance carries the counts, like every other source's: each phase's positions, the not indexed and
    /// the no-peak ones, at the held threshold (mac4DSTEM#480: the grains branch returned before writing them, so a door check
    /// read nil). Mutation: the grains branch returns before the counts - red.
    func testAGrainsRunsProvenanceCarriesTheCounts() {
        func m(_ score: Float) -> OrientationResult {
            var r = OrientationResult.empty
            r.templateIndex = 0; r.score = score
            return r
        }
        let cubic = CrystalOrientationSymmetry(laueClass: .mThreeBarM)
        // Position 0: B wins 0.8 to 0.6 (reliability 25, sure); position 1: A 0.5 to 0.45 (10, not indexed); 2: no peaks.
        let a = MatrixOrientationField(width: 3, height: 1, results: [m(0.6), m(0.5), .empty],
                                       orientations: [matrix_identity_double3x3, matrix_identity_double3x3, nil])
        let b = MatrixOrientationField(width: 3, height: 1, results: [m(0.8), m(0.45), .empty],
                                       orientations: [matrix_identity_double3x3, matrix_identity_double3x3, nil])
        guard let run = GrainsPhaseRun.make(phaseNames: ["A", "B"], symmetries: [cubic, cubic], fields: [a, b],
                                            usablePeakCounts: [5, 5, 0]) else { return XCTFail("the fields fit one scan") }
        let record = PhaseMappingProduct.RunRecord(
            phaseSignature: "fixture", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(),
            libraryEntryCount: 0, matrixEntryIndex: -1, matrixInPlaneDegrees: .nan, worstChanceMatchPercent: 0,
            invAngstromPerPixel: 0.01, qScaleIsPhysical: false, peakCount: 0,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0)),
            orientationSource: .grains)
        let state = AppState()
        state.phaseMapping.publish(grains: run, ranWith: record)
        guard let map = state.phaseMapping.map else { return XCTFail("the grains run published no map") }
        let provenance = state.phaseProvenance(map: map, run: record)
        XCTAssertEqual(provenance["method"], "template_matching_best_phase")
        XCTAssertEqual(provenance["count_0_A"], "0")
        XCTAssertEqual(provenance["count_1_B"], "1")
        XCTAssertEqual(provenance["count_not_indexed"], "1")
        XCTAssertEqual(provenance["count_no_peaks"], "1")
    }

    /// The method choice: grains is its own source, the matrix method returns to the structures, the typed zones stay the matrix
    /// method's. A grains list needs two phases and no matrix; its identity ignores the matrix mark. A map without a matrix gives
    /// every phase a hue of its own, the first the first hue. Mutation: the colour rank shifted for -1 (phase 0 takes the last hue).
    func testTheMethodChoiceAndAMapWithoutAMatrix() throws {
        let product = PhaseMappingProduct()
        XCTAssertEqual(product.method, .matrixWithPrecipitates)
        product.method = .grainsAndPhases
        XCTAssertEqual(product.orientationSource, .grains)
        XCTAssertFalse(product.orientationSource.hasMatrix)
        product.method = .matrixWithPrecipitates
        XCTAssertEqual(product.orientationSource, .structures)
        product.orientationSource = .typedZones
        XCTAssertEqual(product.method, .matrixWithPrecipitates)
        product.method = .matrixWithPrecipitates
        XCTAssertEqual(product.orientationSource, .typedZones, "choosing the method it is in leaves the typed zones")
        XCTAssertEqual(PhaseMappingMethod.grainsAndPhases.title, "Grains and phases (no matrix)")

        product.method = .grainsAndPhases
        let al = try XCTUnwrap(CrystalModelLibrary.model(id: "al_fcc")), mg = try XCTUnwrap(CrystalModelLibrary.model(id: "mg_hcp"))
        product.add(al)
        XCTAssertEqual(product.runRefusal, "Add at least two phases; with one, the Orientation room maps its grains.")
        product.add(mg)
        XCTAssertNil(product.runRefusal)
        let signature = product.phaseSignature
        XCTAssertTrue(signature.hasPrefix("grains;"))
        product.phases[0].isMatrix = false
        product.phases[1].isMatrix = true
        XCTAssertEqual(product.phaseSignature, signature, "a grains run has no matrix")
        product.add(al)
        XCTAssertNotNil(product.runRefusal, "a structure twice")

        XCTAssertEqual(PhaseResultPicture(productKind: "phase_reliability"), .reliability)
        XCTAssertEqual(PhaseResultPicture.reliability.productKind, "phase_reliability")
        let first = PhaseMapPresentation.color(phaseIndex: 0, matrixPhaseIndex: -1)
        let second = PhaseMapPresentation.color(phaseIndex: 1, matrixPhaseIndex: -1)
        XCTAssertTrue(first == PhaseMapPresentation.color(phaseIndex: 1, matrixPhaseIndex: 0), "phase 0 takes the first hue")
        XCTAssertFalse(first == second)
    }
}
