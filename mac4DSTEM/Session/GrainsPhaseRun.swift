//
//  GrainsPhaseRun.swift
//  Role: what a "Grains and phases (no matrix)" run found (mac4DSTEM#252): every phase's template match at every position, the
//        best phase per position and how far ahead of the other phases it is (DiffractoKit `BestPhaseMatching`, ASTAR's phase
//        reliability), and from it the phase map and the phase + orientation field the map views draw. No phase is a matrix.
//        Pure: no SwiftUI, no AppState.
//
//  The reliability threshold is applied here, not in the run: a position whose winner is less than `reliableAbove` ahead of the
//  best other phase is drawn as not indexed, and moving the threshold re-reads the held results without matching again.
//

import Foundation
import simd
#if canImport(DSTEMCore)
import DSTEMCore
import DiffractoCore
#endif
import DiffractoOrientation

package nonisolated struct GrainsPhaseRun: Sendable {
    package let width: Int
    package let height: Int
    /// The phases in the phase list's order (the map's phase indices).
    package let phaseNames: [String]
    /// Each phase's crystal symmetry (its template library's), by phase index.
    package let symmetries: [CrystalOrientationSymmetry]
    /// Per position, row-major: the competition between the phases.
    package let best: [BestPhaseResult]
    /// Per position: the winner's crystal orientation (its library's orientation matrix), nil where no phase matched.
    package let orientations: [simd_double3x3?]
    /// Per position: how many peaks the matching used (inside the reach, outside the direct beam). 0 is "no peaks".
    package let usablePeakCounts: [Int]

    package init(width: Int, height: Int, phaseNames: [String], symmetries: [CrystalOrientationSymmetry],
                 best: [BestPhaseResult], orientations: [simd_double3x3?], usablePeakCounts: [Int]) {
        self.width = width; self.height = height; self.phaseNames = phaseNames; self.symmetries = symmetries
        self.best = best; self.orientations = orientations; self.usablePeakCounts = usablePeakCounts
    }

    /// Why a run could not be made, in the kit's words.
    package struct Refusal: Error, Sendable {
        package let reason: String
        package init(reason: String) { self.reason = reason }
    }

    /// ASTAR's reading of the reliability: 15 or more is a sure phase (DiffractoKit `BestPhaseMatching.publishedReliableAbove`).
    package static let defaultReliableAbove = Double(BestPhaseMatching.publishedReliableAbove)

    /// From each phase's template match over the same scan (in phase order, as `MatrixOrientationField.matrixOrientations` returns
    /// it), the phases' symmetries, and the usable peak count per position. Nil when the fields do not fit one scan.
    package static func make(phaseNames: [String], symmetries: [CrystalOrientationSymmetry], fields: [MatrixOrientationField],
                             usablePeakCounts: [Int]) -> GrainsPhaseRun? {
        guard let first = fields.first, !phaseNames.isEmpty, fields.count == phaseNames.count,
              symmetries.count == phaseNames.count else { return nil }
        let n = first.width * first.height
        guard n > 0, usablePeakCounts.count == n,
              fields.allSatisfy({ $0.width == first.width && $0.height == first.height
                  && $0.results.count == n && $0.orientations.count == n }) else { return nil }
        var best = [BestPhaseResult](repeating: .none, count: n)
        var orientations = [simd_double3x3?](repeating: nil, count: n)
        for i in 0..<n {
            let r = BestPhaseMatching.best(of: fields.map { $0.results[i] })
            best[i] = r
            if r.phaseIndex >= 0 { orientations[i] = fields[r.phaseIndex].orientations[i] }
        }
        return GrainsPhaseRun(width: first.width, height: first.height, phaseNames: phaseNames, symmetries: symmetries,
                              best: best, orientations: orientations, usablePeakCounts: usablePeakCounts)
    }

    /// The run: each phase's template library to the reach (`PhaseOrientationCandidate`, the settings every phase shares, so the
    /// scores compare: `BestPhaseMatching.areComparable`), every position matched against each (`matrixOrientations`, the peaks
    /// the structures run uses: outside the direct beam, inside `maximumVectorInvAngstrom`), then the best phase per position.
    /// - Returns: nil when cancelled or the scan does not fit its size.
    /// - Throws: `Refusal` with the kit's words when a structure cannot be matched, or the libraries do not compare.
    package static func run(scan: [[SIMD2<Double>]], scanWidth: Int, scanHeight: Int,
                            phases: [(name: String, crystal: CrystalStructure)],
                            reachInvAngstrom: Double, maximumVectorInvAngstrom: Double, directBeamRadiusInvAngstrom: Double,
                            originX: Float, originY: Float, invAngstromPerPixel: Double,
                            isCancelled: (@Sendable () -> Bool)? = nil,
                            progress: (@Sendable (Double) -> Void)? = nil) throws -> GrainsPhaseRun? {
        guard !phases.isEmpty, scanWidth > 0, scanHeight > 0, scan.count == scanWidth * scanHeight else { return nil }
        var candidates: [PhaseOrientationCandidate] = []
        for phase in phases {
            do { candidates.append(try PhaseOrientationCandidate(name: phase.name, crystal: phase.crystal, kMax: reachInvAngstrom)) }
            catch { throw Refusal(reason: "\(phase.name): \(error)") }
            if isCancelled?() == true { return nil }
        }
        guard BestPhaseMatching.areComparable(candidates.map(\.matcher.library)) else {
            throw Refusal(reason: "the phases' template libraries are not on one polar grid, so their scores do not compare")
        }
        let usable = scan.map { peaks in
            peaks.reduce(0) { count, p in
                count + (PhaseVectorMatcher.experimentalVector(
                    peak: p, originX: originX, originY: originY, invAngstromPerPixel: invAngstromPerPixel,
                    directBeamRadiusInvAngstrom: directBeamRadiusInvAngstrom,
                    maximumVectorInvAngstrom: maximumVectorInvAngstrom) == nil ? 0 : 1)
            }
        }
        var fields: [MatrixOrientationField] = []
        let share = 1 / Double(candidates.count)
        for (k, candidate) in candidates.enumerated() {
            let phaseProgress: (@Sendable (Double) -> Void)?
            if let progress { phaseProgress = { progress((Double(k) + $0) * share) } } else { phaseProgress = nil }
            guard let field = PhaseVectorMatcher.matrixOrientations(
                scan: scan, scanWidth: scanWidth, scanHeight: scanHeight, matcher: candidate.matcher,
                originX: originX, originY: originY, invAngstromPerPixel: invAngstromPerPixel,
                directBeamRadiusInvAngstrom: directBeamRadiusInvAngstrom, maximumVectorInvAngstrom: maximumVectorInvAngstrom,
                isCancelled: isCancelled, progress: phaseProgress) else { return nil }
            fields.append(field)
        }
        return make(phaseNames: phases.map(\.name), symmetries: candidates.map(\.matcher.library.orientationSymmetry),
                    fields: fields, usablePeakCounts: usable)
    }

    /// The evidence for one position in one line: the winner's correlation index, the best other phase's, the reliability
    /// against the threshold.
    package func evidenceLine(at i: Int, reliableAbove: Double) -> String {
        guard best.indices.contains(i) else { return "" }
        if usablePeakCounts[i] == 0 { return "No peaks at this position." }
        let b = best[i]
        guard b.phaseIndex >= 0, phaseNames.indices.contains(b.phaseIndex) else {
            return "No phase's templates matched the \(usablePeakCounts[i]) peaks here."
        }
        func index(_ v: Float) -> String { String(format: "%.3f", Double(v)) }
        var line = "\(phaseNames[b.phaseIndex]) — correlation \(index(b.score))"
        if phaseNames.indices.contains(b.runnerUpPhaseIndex) {
            line += ", \(phaseNames[b.runnerUpPhaseIndex]) next at \(index(b.runnerUpScore))"
        }
        let reliability = String(format: "%.0f", Double(b.reliability))
        let threshold = String(format: "%.0f", reliableAbove)
        line += isReliable(i, reliableAbove: reliableAbove)
            ? "; reliability \(reliability) (sure from \(threshold))."
            : "; reliability \(reliability), below \(threshold): not indexed."
        return line
    }

    /// Whether position `i` takes its winner at this threshold: a phase won, it has an orientation, and it is at least
    /// `reliableAbove` ahead of the best other phase.
    package func isReliable(_ i: Int, reliableAbove: Double) -> Bool {
        best[i].phaseIndex >= 0 && orientations[i] != nil && Double(best[i].reliability) >= reliableAbove
    }

    /// The phase map at a threshold: `.indexed` with the winner where it is reliable, `.notIndexed` where peaks were matched and
    /// no phase is sure, `.noData` where no peak was usable. No position is `.matrix` (`matrixPhaseIndex` is -1). The score is
    /// the winner's correlation index (not a distance), the runner-up's likewise.
    package func phaseMap(reliableAbove: Double) -> PhaseMap {
        var map = PhaseMap(width: width, height: height, matrixEntryIndex: -1, phaseNames: phaseNames, matrixPhaseIndex: -1)
        for i in map.results.indices where i < best.count {
            var r = PhaseVectorResult()
            let b = best[i]
            r.survivingCount = Int32(clamping: usablePeakCounts[i])
            if usablePeakCounts[i] == 0 {
                r.verdict = .noData
            } else if isReliable(i, reliableAbove: reliableAbove) {
                r.verdict = .indexed
                r.phaseIndex = Int32(b.phaseIndex)
                r.entryIndex = Int32(b.orientation.templateIndex)
                r.score = b.score
                r.runnerUpPhaseIndex = Int32(b.runnerUpPhaseIndex)
                r.runnerUpScore = b.runnerUpPhaseIndex >= 0 ? b.runnerUpScore : .nan
            } else {
                r.verdict = .notIndexed
            }
            map.results[i] = r
        }
        return map
    }

    /// Phase and orientation at a threshold, in the shape the orientation map per phase draws (#293): the reliable positions with
    /// their winner and its orientation, the score the winner's correlation index, the reliability of every position that had a
    /// winner (NaN elsewhere), so the reliability map shows the unsure positions too.
    package func orientationField(reliableAbove: Double) -> PhaseOrientationField {
        let n = width * height
        var phase = [Int](repeating: -1, count: n)
        var orientation = [simd_double3x3?](repeating: nil, count: n)
        var score = [Double](repeating: .nan, count: n)
        var reliability = [Double](repeating: .nan, count: n)
        for i in 0..<min(n, best.count) {
            if best[i].phaseIndex >= 0 { reliability[i] = Double(best[i].reliability) }
            guard isReliable(i, reliableAbove: reliableAbove) else { continue }
            phase[i] = best[i].phaseIndex; orientation[i] = orientations[i]; score[i] = Double(best[i].score)
        }
        return PhaseOrientationField(width: width, height: height, phaseNames: phaseNames, symmetries: symmetries,
                                     phaseIndex: phase, orientation: orientation, score: score, reliability: reliability)
    }

    /// How many positions each phase holds at this threshold, and how many are unsure (a winner below the threshold).
    package func counts(reliableAbove: Double) -> (perPhase: [Int], unsure: Int) {
        var perPhase = [Int](repeating: 0, count: phaseNames.count)
        var unsure = 0
        for i in best.indices where usablePeakCounts[i] > 0 {
            if isReliable(i, reliableAbove: reliableAbove), perPhase.indices.contains(best[i].phaseIndex) {
                perPhase[best[i].phaseIndex] += 1
            } else {
                unsure += 1
            }
        }
        return (perPhase, unsure)
    }
}
