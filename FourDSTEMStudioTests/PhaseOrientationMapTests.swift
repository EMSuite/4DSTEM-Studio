//
//  PhaseOrientationMapTests.swift
//  mac4DSTEM#293: phase and orientation at every position of a run from the structures, and the orientation map of one phase
//  (IPF-Z) drawn from it. The pure field and picture on a hand-made field; then the app's own run on the simulated Al-Mg-Si demo,
//  version 3, where every planted beta'' needle is one variant of Andersen's relationship (skipped when the file is not on this
//  machine; `MACEM_REFERENCES` names the folder that holds `mac4DSTEM/`, otherwise the repo's own `References`).
//

import XCTest
import simd
import DSTEMCore
import DSTEMSession
import DiffractoCore
import DiffractoOrientation
@testable import FourDSTEMStudio

@MainActor
final class PhaseOrientationMapTests: XCTestCase {
    private static var references: URL {
        if let root = ProcessInfo.processInfo.environment["MACEM_REFERENCES"] { return URL(fileURLWithPath: root).appendingPathComponent("mac4DSTEM") }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("References")
    }

    /// Two phases on a 2 x 2 scan: a cubic matrix on [001], a monoclinic precipitate, a position with no phase, a matrix position
    /// without an orientation. The precipitate's picture colours its one position by the kit's 2/m key, greys the matrix
    /// positions, leaves the empty one transparent; the validity mask holds the precipitate's position only.
    /// Mutations: the beam taken from the first column (the colour changes); other phases left transparent (alpha 0, not grey).
    func testOnePhasesPictureColoursItsPositionsByTheirBeamDirection() throws {
        let cubic = CrystalOrientationSymmetry(laueClass: .mThreeBarM), mono = CrystalOrientationSymmetry(laueClass: .twoOverM)
        let tilt = simd_double3x3(simd_quatd(angle: 0.4, axis: simd_normalize(SIMD3(1, 2, 0.5))))
        let field = PhaseOrientationField(width: 2, height: 2, phaseNames: ["Al", "beta''"], symmetries: [cubic, mono],
                                          phaseIndex: [0, 1, -1, 0], orientation: [matrix_identity_double3x3, tilt, nil, nil],
                                          score: [0.9, 0.01, .nan, .nan])
        XCTAssertEqual(field.count(of: 1), 1)
        XCTAssertEqual(field.count(of: 0), 1, "a matrix position without an orientation is not counted")
        let picture = field.ipfZImage(phase: 1)
        XCTAssertEqual(picture.width, 2); XCTAssertEqual(picture.rgba.count, 16)
        let c = try mono.ipfColor(direction: tilt.columns.2, key: .native)
        let expected = [c.x, c.y, c.z].map { UInt8((min(1, max(0, $0)) * 255).rounded()) }
        XCTAssertEqual(Array(picture.rgba[4..<7]), expected)
        XCTAssertEqual(picture.rgba[7], 255)
        let grey = PhaseOrientationField.otherPhaseGrey
        XCTAssertEqual(Array(picture.rgba[0..<4]), [grey, grey, grey, 255], "another phase's position is grey")
        XCTAssertEqual(picture.rgba[11], 0, "a position with no phase is transparent")
        XCTAssertEqual(Array(picture.rgba[12..<16]), [grey, grey, grey, 255])
        XCTAssertEqual(field.validity(phase: 1), [false, true, false, false])
        XCTAssertEqual(field.validity(phase: 0), [true, false, false, false])
        // The matrix's own picture: [001] in the cubic key.
        let m = try cubic.ipfColor(direction: SIMD3(0, 0, 1), key: .native)
        XCTAssertEqual(Array(field.ipfZImage(phase: 0).rgba[0..<3]), [m.x, m.y, m.z].map { UInt8((min(1, max(0, $0)) * 255).rounded()) })
    }

    /// The legend follows the phase's symmetry: the three drawn keys for m-3m, 6/mmm and 2/m, the fundamental zone for the rest.
    func testTheKeyFollowsThePhasesSymmetry() {
        XCTAssertEqual(IPFLegendKind.kind(forLaueClass: .mThreeBarM), .cubic)
        XCTAssertEqual(IPFLegendKind.kind(forLaueClass: .sixOverMmm), .hexagonal)
        XCTAssertEqual(IPFLegendKind.kind(forLaueClass: .twoOverM), .monoclinic)
        XCTAssertEqual(IPFLegendKind.kind(forLaueClass: .fourOverMmm), .other(.fourOverMmm))
        XCTAssertEqual(IPFLegendKind.kind(forLaueClass: nil), .cubic)
        XCTAssertEqual(PhaseResultPicture(productKind: "phase_orientation_ipf_z"), .orientation)
        XCTAssertEqual(PhaseResultPicture.orientation.productKind, "phase_orientation_ipf_z")
        XCTAssertEqual(PhaseResultPicture.control(owning: .orientation, displayedKind: "phase_orientation_ipf_z").target, .phaseMap)
        XCTAssertEqual(PhaseResultPicture.control(owning: .orientation, displayedKind: "phase_map").title, "Show Orientation")
    }

    private struct Truth: Decodable {
        struct Precipitate: Decodable { let name: String; let kind: String; let variant: Int?; let pixels_y_x: [[Int]] }
        let grain_label_map: [[Int]]
        let precipitates: [Precipitate]
    }

    /// The demo, version 3, mapped from aluminium and the beta'' CIF (no zone typed), then Show Orientation. Measured 2026-11-15:
    /// - every beta'' position carries an orientation, and the picture colours exactly those (151 positions), keyed 2/m;
    /// - each planted needle's positions sit at its planted variant: the six end-on needles at their own variant (E1, E5: 1;
    ///   E2: 4; E3, E6: 5; E4: 8), the three in the foil plane at their variant or its partner, the two the pattern cannot tell
    ///   apart (DiffractoKit#107: H1 2 or 3, H2 6 or 7, V1 9 or 11), within 3 degrees plus the learned relationship's distance.
    /// - the matrix's own picture holds every matrix position.
    func testTheDemosNeedlesSitAtTheirPlantedVariants() async throws {
        let folder = Self.references.appendingPathComponent("demo-edx-v3")
        let file = folder.appendingPathComponent("AlMgSi_4D_EDX.dm4")
        let cif = Self.references.appendingPathComponent("crystal-structures/beta_double_prime_Mg5Si6.cif")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path) && FileManager.default.fileExists(atPath: cif.path),
                          "demo-edx-v3 or the beta'' CIF is not on this machine")
        let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: folder.appendingPathComponent("truth_edx.json")))
        let width = truth.grain_label_map[0].count

        let state = AppState()
        await state.openFileAsync(url: file)
        _ = try XCTUnwrap(state.descriptor, state.statusText)
        await state.calibrateOrigin()
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        let beta = try CIFModelImport.crystalModel(from: try String(contentsOf: cif, encoding: .utf8), fileBaseName: "beta_double_prime_Mg5Si6")
        let al = try XCTUnwrap(CrystalModelLibrary.model(id: "al_fcc"))
        state.phaseMapping.add(al)
        state.phaseMapping.add(beta)
        state.navigation.analysisMode = .phaseMapping
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, state.statusText)
        let map = try XCTUnwrap(state.phaseMapping.map)
        let run = try XCTUnwrap(state.phaseMapping.lastStructureRun)
        XCTAssertNil(state.phaseOrientationBlocker)
        let field = try XCTUnwrap(state.phaseOrientationField)
        XCTAssertEqual(state.resolvedOrientationPhase, 1, "the first candidate is drawn by default")

        // Every beta'' position of the map carries an orientation, and the picture shows exactly those.
        let betaPositions = map.results.indices.filter { map.results[$0].verdict == .indexed && map.results[$0].phaseIndex == 1 }
        XCTAssertEqual(field.count(of: 1), betaPositions.count)
        state.showPhaseResult(.orientation)
        XCTAssertEqual(state.displayedProduct?.kind, "phase_orientation_ipf_z")
        XCTAssertEqual(state.displayedProduct?.provenance["orientation_symmetry"], "2/m")
        XCTAssertEqual(state.displayedProduct?.provenance["orientation_positions"], String(betaPositions.count))
        XCTAssertEqual(field.validity(phase: 1).filter { $0 }.count, betaPositions.count)
        let matrixPositions = map.results.filter { $0.verdict == .matrix }.count
        XCTAssertEqual(field.count(of: 0), matrixPositions, "every matrix position carries the matrix orientation")
        state.selectOrientationPhase(0)
        XCTAssertEqual(state.displayedProduct?.provenance["orientation_phase"], map.phaseNames[0], "choosing a phase redraws the map on screen")
        state.selectOrientationPhase(1)

        // Each needle at its planted variant.
        let setup = try VariantSetup(precipitate: beta.structure, matrix: al.structure, preset: .betaDoublePrimeInAl)
        let offset = ObjectVariantJoin.learnedOffsetDegrees(run, candidate: 0, named: setup)
        let partners: [String: Set<Int>] = ["H1": [2, 3], "H2": [6, 7], "V1": [9, 11]]
        var lines: [String] = []
        for p in truth.precipitates where p.kind != "other_phase" && !p.name.hasPrefix("Q") {
            let planted = try XCTUnwrap(p.variant, p.name)
            let accepted = partners[p.name] ?? [planted]
            var votes: [Int: Int] = [:], worst = 0.0, positions = 0
            for yx in p.pixels_y_x {
                let i = yx[0] * width + yx[1]
                guard field.phaseIndex[i] == 1, let precipitate = field.orientation[i], let matrix = run.matrixOrientations[i] else { continue }
                let frame = ObjectVariantAssigner.canonicalMatrixFrame(matrix, crystal: al.structure)
                let hit = try XCTUnwrap(setup.set.nearestVariant(matrixOrientation: frame, precipitateOrientation: precipitate))
                votes[hit.index + 1, default: 0] += 1
                worst = max(worst, hit.disorientationRad * 180 / .pi)
                positions += 1
            }
            let top = try XCTUnwrap(votes.max { $0.value < $1.value }, "\(p.name) has no beta'' position")
            lines.append("\(p.name): planted \(planted), votes \(votes.sorted { $0.key < $1.key }), worst \(String(format: "%.2f", worst)) deg")
            XCTAssertTrue(accepted.contains(top.key), "\(p.name): its positions sit at variant \(top.key), planted \(planted)")
            XCTAssertLessThan(worst, 3 + offset, "\(p.name): a position lies \(worst) degrees from its variant")
            XCTAssertGreaterThan(positions, 0)
        }
        print("ORIENTATIONS DEMO | offset \(String(format: "%.2f", offset)) | " + lines.joined(separator: " | "))
    }
}
