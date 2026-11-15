//
//  PhaseOrientationField.swift
//  Role: phase and orientation together at every scan position (mac4DSTEM#293), the shape an orientation map per phase is drawn
//        from: which phase, its crystal orientation, the score that chose it. A run from the structures fills it today (the matrix
//        orientation where the map says matrix, the precipitate orientation the second pass found where it says a phase);
//        "Grains and phases (no matrix)" (#252, DiffractoKit#121) is to fill the same shape, so one map view serves both.
//        Pure: no SwiftUI, no AppState; the kit colours (`CrystalOrientationSymmetry.ipfColor`, its native keys).
//
//  Orientation convention: the kit's, columns = the lab x, y and the beam in the crystal's Cartesian frame, so the IPF-Z pole of a
//  position is its third column. The Laue groups hold the inversion, so the sign of the beam does not change a colour.
//

import Foundation
import simd
#if canImport(DSTEMCore)
import DSTEMCore
import DiffractoCore
import DiffractoOrientation
#endif

package nonisolated struct PhaseOrientationField: Sendable {
    package let width: Int
    package let height: Int
    /// The phases in the phase list's order (the map's phase indices).
    package let phaseNames: [String]
    /// Each phase's crystal symmetry, by phase index: it reduces the orientation and picks the IPF key.
    package let symmetries: [CrystalOrientationSymmetry]
    /// Per position, row-major: the phase index, or -1 where no phase was found (not indexed, no peaks).
    package let phaseIndex: [Int]
    /// Per position: the crystal orientation of that phase, nil where none was found.
    package let orientation: [simd_double3x3?]
    /// Per position: the score that chose the phase (the matrix's template correlation, a precipitate's vector-matching
    /// distance in Å⁻¹); NaN where none. Kept for the reliability map of #252; not drawn here.
    package let score: [Double]

    package init(width: Int, height: Int, phaseNames: [String], symmetries: [CrystalOrientationSymmetry],
                 phaseIndex: [Int], orientation: [simd_double3x3?], score: [Double]) {
        self.width = width; self.height = height; self.phaseNames = phaseNames; self.symmetries = symmetries
        self.phaseIndex = phaseIndex; self.orientation = orientation; self.score = score
    }

    /// From a run from the structures and its map in list order (`PhaseMappingProduct.mapInListOrder`). `candidateIndex[p]` is
    /// phase p's index among the run's candidates, nil for the matrix (the bookkeeping `ObjectVariantJoin.StructureRun` keeps).
    /// A position takes the matrix orientation where the map says matrix, and the second pass's orientation where it says a phase
    /// and the second pass found that phase there. Nil when the run, the map and the list do not fit together.
    package static func make(structureRun run: StructurePhaseMapping, map: PhaseMap, candidateIndex: [Int?]) -> PhaseOrientationField? {
        let n = map.results.count
        let verdicts = run.classification.verdicts
        guard n == map.width * map.height, run.matrixOrientations.count == n, verdicts.count == n,
              run.matrixField.results.count == n, candidateIndex.count == map.phaseNames.count,
              map.phaseNames.indices.contains(map.matrixPhaseIndex), candidateIndex[map.matrixPhaseIndex] == nil else { return nil }
        var symmetries: [CrystalOrientationSymmetry] = []
        for (p, k) in candidateIndex.enumerated() {
            if let k {
                guard run.candidateSymmetries.indices.contains(k), p != map.matrixPhaseIndex else { return nil }
                symmetries.append(run.candidateSymmetries[k])
            } else {
                guard p == map.matrixPhaseIndex else { return nil }
                symmetries.append(run.matrixSymmetry)
            }
        }
        var phase = [Int](repeating: -1, count: n)
        var orientation = [simd_double3x3?](repeating: nil, count: n)
        var score = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let r = map.results[i]
            switch r.verdict {
            case .matrix:
                guard let m = run.matrixOrientations[i] else { continue }
                phase[i] = map.matrixPhaseIndex; orientation[i] = m; score[i] = Double(run.matrixField.results[i].score)
            case .indexed:
                let p = Int(r.phaseIndex)
                guard candidateIndex.indices.contains(p), let k = candidateIndex[p],
                      verdicts[i].verdict == .indexed, verdicts[i].phaseIndex == k, let o = verdicts[i].orientation else { continue }
                phase[i] = p; orientation[i] = o; score[i] = verdicts[i].score
            case .notIndexed, .noData:
                continue
            }
        }
        return PhaseOrientationField(width: map.width, height: map.height, phaseNames: map.phaseNames, symmetries: symmetries,
                                     phaseIndex: phase, orientation: orientation, score: score)
    }

    /// How many positions of `phase` carry an orientation.
    package func count(of phase: Int) -> Int {
        zip(phaseIndex, orientation).reduce(0) { $0 + ($1.0 == phase && $1.1 != nil ? 1 : 0) }
    }

    /// The grey of a position that holds another phase: drawn, and hatched by the validity mask, so the phase's own positions
    /// stand out without hiding where the others are.
    package static let otherPhaseGrey: UInt8 = 77

    /// The IPF-Z map of one phase: each of its positions coloured by the beam direction in the crystal (the phase's native key),
    /// every other position with a phase in `otherPhaseGrey`, a position with none transparent.
    package func ipfZImage(phase: Int) -> RGBAImage {
        var out = [UInt8](repeating: 0, count: max(0, width * height * 4))
        let symmetry = symmetries.indices.contains(phase) ? symmetries[phase] : nil
        for i in 0..<min(phaseIndex.count, width * height) {
            guard phaseIndex[i] >= 0 else { continue }
            var rgb = SIMD3<UInt8>(repeating: Self.otherPhaseGrey)
            if phaseIndex[i] == phase, let o = orientation[i], let symmetry,
               let c = try? symmetry.ipfColor(direction: o.columns.2, key: .native) {
                rgb = SIMD3(UInt8((min(1, max(0, c.x)) * 255).rounded()), UInt8((min(1, max(0, c.y)) * 255).rounded()),
                            UInt8((min(1, max(0, c.z)) * 255).rounded()))
            }
            out[i * 4] = rgb.x; out[i * 4 + 1] = rgb.y; out[i * 4 + 2] = rgb.z; out[i * 4 + 3] = 255
        }
        return RGBAImage(width: width, height: height, rgba: out)
    }

    /// The positions `ipfZImage(phase:)` colours: the phase's own positions with an orientation.
    package func validity(phase: Int) -> [Bool] {
        zip(phaseIndex, orientation).map { $0.0 == phase && $0.1 != nil }
    }
}
