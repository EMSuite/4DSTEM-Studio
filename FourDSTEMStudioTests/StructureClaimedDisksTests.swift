//
//  StructureClaimedDisksTests.swift
//  mac4DSTEM#295: "Show claimed disks" for a map made from the structures, the default method since 5.3. The kit replays the
//  run (`StructurePhaseMapping.claims(at:peaks:)`, DiffractoKit#130); the app moves the kit's phase indices to the list's and
//  hands the claims to the overlay. The index move on its own; then the app's run on the simulated Al-Mg-Si demo, version 3
//  (skipped when the file is not on this machine; `MACEM_REFERENCES` names the folder that holds `mac4DSTEM/`).
//

import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoCore
import DiffractoOrientation
@testable import FourDSTEMStudio

@MainActor
final class StructureClaimedDisksTests: XCTestCase {
    private static var references: URL {
        if let root = ProcessInfo.processInfo.environment["MACEM_REFERENCES"] { return URL(fileURLWithPath: root).appendingPathComponent("mac4DSTEM") }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("References")
    }

    /// The kit counts the matrix as phase 0 and the candidates after it; the list may hold them in any order. Matrix second,
    /// two candidates: kit 0 → list 1, kit 1 → list 0, kit 2 → list 2; the other claims unchanged; an index past the
    /// candidates refused. Mutation: the candidates' slots read without the − 1 (kit 1 → list 2).
    func testTheKitsPhaseIndicesMoveToTheListsOrder() throws {
        let claims: [PhaseDiskClaim] = [.notMatched, .matrix, .phase(0), .phase(1), .phase(2), .unexplained]
        let moved = try XCTUnwrap(PhaseMappingProduct.claimsInListOrder(claims, matrixSlot: 1, candidateSlots: [0, 2]))
        XCTAssertEqual(moved, [.notMatched, .matrix, .phase(1), .phase(0), .phase(2), .unexplained])
        XCTAssertNil(PhaseMappingProduct.claimsInListOrder([.phase(3)], matrixSlot: 1, candidateSlots: [0, 2]))
    }

    private struct Truth: Decodable {
        struct Precipitate: Decodable { let name: String; let kind: String; let pixels_y_x: [[Int]] }
        let grain_label_map: [[Int]]
        let precipitates: [Precipitate]
    }

    /// The demo mapped from aluminium and the beta'' CIF, the overlay's own steps at every planted beta'' needle's centre and at a
    /// plain matrix position: the claims replay the map, the matrix claims as many disks as the removal took and beta'' as many
    /// as the classification matched, in the list's phase index (beta'' is 1). Measured 2026-11-15.
    func testTheDemosNeedlesShowTheirClaimedDisks() async throws {
        let folder = Self.references.appendingPathComponent("demo-edx-v3")
        let file = folder.appendingPathComponent("AlMgSi_4D_EDX.dm4")
        let cif = Self.references.appendingPathComponent("crystal-structures/beta_double_prime_Mg5Si6.cif")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path) && FileManager.default.fileExists(atPath: cif.path),
                          "demo-edx-v3 or the beta'' CIF is not on this machine")
        let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: folder.appendingPathComponent("truth_edx.json")))
        let width = truth.grain_label_map[0].count

        let state = AppState()
        await state.openFileAsync(url: file)
        let descriptor = try XCTUnwrap(state.descriptor, state.statusText)
        await state.calibrateOrigin()
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        let beta = try CIFModelImport.crystalModel(from: try String(contentsOf: cif, encoding: .utf8), fileBaseName: "beta_double_prime_Mg5Si6")
        state.phaseMapping.add(try XCTUnwrap(CrystalModelLibrary.model(id: "al_fcc")))
        state.phaseMapping.add(beta)
        state.navigation.analysisMode = .phaseMapping
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, state.statusText)
        let map = try XCTUnwrap(state.phaseMapping.map)
        let run = try XCTUnwrap(state.phaseMapping.lastStructureRun)
        let raw = try XCTUnwrap(state.resultPresentation.braggVectors)

        func claims(at scan: Int) throws -> [PhaseDiskClaim] {
            let calibrated = state.calibratedBraggVectors(raw, descriptor: descriptor, positions: [scan])
            let peaks = calibrated.vectors.peaks[scan].map(\.phaseScanPosition)
            return try XCTUnwrap(PhaseMappingProduct.claimsInListOrder(run.claims(at: scan, peaks: peaks), matrixSlot: 0,
                                                                       candidateSlots: [1]))
        }
        var lines: [String] = []
        for p in truth.precipitates where p.kind != "other_phase" && !p.name.hasPrefix("Q") {
            let centre = p.pixels_y_x[p.pixels_y_x.count / 2]
            let scan = centre[0] * width + centre[1]
            let r = map.results[scan]
            guard r.verdict == .indexed else { XCTFail("\(p.name): centre not indexed"); continue }
            let c = try claims(at: scan)
            let matrix = c.filter { $0 == .matrix }.count, own = c.filter { $0 == .phase(1) }.count
            lines.append("\(p.name): matrix \(matrix) (removed \(r.removedCount)), beta'' \(own) (matched \(r.matchedCount)), unexplained \(c.filter { $0 == .unexplained }.count)")
            XCTAssertEqual(matrix, Int(r.removedCount), p.name)
            XCTAssertEqual(own, Int(r.matchedCount), p.name)
            XCTAssertGreaterThan(own, 0, p.name)
        }
        // A plain matrix position: the matrix only.
        let plain = try XCTUnwrap(map.results.indices.first { map.results[$0].verdict == .matrix })
        let c = try claims(at: plain)
        XCTAssertFalse(c.contains(.phase(1)))
        XCTAssertEqual(c.filter { $0 == .matrix }.count, Int(map.results[plain].removedCount))
        print("CLAIMS DEMO | " + lines.joined(separator: " | "))
    }
}
