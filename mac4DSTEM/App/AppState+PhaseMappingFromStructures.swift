//
//  AppState+PhaseMappingFromStructures.swift
//  Role: Map Phases with the orientations found from the structures alone (mac4DSTEM#184): the structures and the
//        detected disks in, the phase of every position out, no zone axis typed.
//
//  The method is DiffractoKit's `PhaseVectorMatcher.mapFromStructures`: the matrix orientation of every position by
//  template matching, one orientation per grain, the matrix's spots removed, then each candidate's orientations searched,
//  its relationship to the matrix learned from the strong positions and every position scored against the variants
//  (vector matching after Thronsen et al., Ultramicroscopy 255 (2024) 113861; the proposals by template matching after
//  Ophus et al., Microsc. Microanal. 28 (2022) 390). This file only hands the kit its inputs and publishes what it returns.
//

import ShellLayout
import Foundation
#if canImport(DSTEMCore)
import DiffractoCore
import DSTEMCore
import DSTEMSession
#endif
import DiffractoOrientation

/// Why the kit refused a structures run, in its own words.
struct PhaseSearchRefusal: Error, Sendable { let reason: String }

extension AppState {

    /// One line per candidate phase on the relationship a structures run learned for it.
    nonisolated static func learnedRelationshipLines(names: [String], relationships: [[LearnedOrientationRelationship]]) -> [String] {
        zip(names, relationships).map { name, learned in
            guard let best = learned.max(by: { $0.positionCount < $1.positionCount }) else {
                return "\(name): no relationship to the matrix learned (too few strong positions)"
            }
            let spread = String(format: "%.1f", best.spreadRad * 180 / .pi)
            let more = learned.count > 1 ? ", and \(learned.count - 1) more" : ""
            return "\(name): relationship to the matrix learned from \(best.positionCount) positions (spread \(spread)°)\(more)"
        }
    }

    /// Map Phases, orientations from the structures. Called by `runPhaseMapping` after its refusals (stale disks, the
    /// list's own refusal, no disks, no physical Q scale), so none of them is repeated here.
    func runPhaseMappingFromStructures() async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("Open a dataset first.") }
        guard let rawVectors = resultPresentation.braggVectors else { return .failed("Detect Bragg disks first.") }
        let slots = phaseMapping.phases
        guard let matrixSlot = slots.firstIndex(where: \.isMatrix) else { return .failed("Mark one phase as the matrix.") }
        let candidateSlots = slots.indices.filter { !slots[$0].isMatrix }
        guard !candidateSlots.isEmpty else { return .failed("Add a candidate phase to look for.") }

        let referenceSettings = phaseMapping.reference
        let matchSettings = phaseMapping.matching
        let phaseSignature = phaseMapping.phaseSignature
        let calibrated = calibratedBraggVectors(rawVectors, descriptor: descriptor)
        let origin = calibrated.origin.point
        // The reach is the typed path's library reach (the nearest detector edge, at most Max |q|), and the peaks are cut
        // there as for a typed run (`matchingWithinLibraryReach`).
        let reach = phaseLibraryKMax(setting: referenceSettings.kMaxInvAngstrom, origin: origin, descriptor: descriptor)
        let cut = Self.matchingWithinLibraryReach(matchSettings, libraryKMaxInvAngstrom: reach).maximumVectorInvAngstrom
        let settings = StructurePhaseMappingSettings(
            reachInvAngstrom: reach, maximumVectorInvAngstrom: cut,
            matrixToleranceInvAngstrom: matchSettings.matrixToleranceInvAngstrom,
            pairRadiusInvAngstrom: matchSettings.pairRadiusInvAngstrom,
            residualCutoffInvAngstrom: matchSettings.residualCutoffInvAngstrom,
            directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom)
        let matrix = StructurePhase(name: slots[matrixSlot].model.displayName, crystal: slots[matrixSlot].model.structure)
        // A phase's own excitation slab, or the one default (`structuresExcitationSlabDefault`).
        let slabs = candidateSlots.map { slots[$0].excitationSlabInvAngstrom ?? PhaseMappingProduct.structuresExcitationSlabDefault }
        let candidates = zip(candidateSlots, slabs).map { index, slab in
            StructurePhase(name: slots[index].model.displayName, crystal: slots[index].model.structure, excitationSlabInvAngstrom: slab)
        }

        let calibrationStamp = PhaseMappingProduct.CalibrationStamp(
            calibration: calibrationSession.calibration, referenceOrigin: origin)
        let scale = acomScaleSemantics
        let invAngstromPerPixel = scale.invAngstromPerPixel

        let cancellation = beginCancellableOperation(
            "Phase mapping",
            status: StructurePhaseMappingStage.matrix.status,
            totalUnits: calibrated.vectors.peaks.count
        )
        defer { finishCancellableOperation(cancellation) }
        let epoch = datasetSession.epoch
        let stages = StructurePhaseMappingStageLog(starting: .matrix)   // the begin status above named it
        let progress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in
                self?.reportStructurePhaseMappingProgress(fraction, cancellation: cancellation, stages: stages)
            }
        }

        let scan = calibrated.vectors.phaseScan
        let scanWidth = calibrated.vectors.scanWidth, scanHeight = calibrated.vectors.scanHeight
        // The kit's refusal travels as its words: the error type stays in the kit.
        let outcome: Result<StructurePhaseMapping?, PhaseSearchRefusal> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try PhaseVectorMatcher.mapFromStructures(
                    scan: scan, scanWidth: scanWidth, scanHeight: scanHeight,
                    matrix: matrix, candidates: candidates, settings: settings,
                    originX: origin.x, originY: origin.y, invAngstromPerPixel: invAngstromPerPixel,
                    isCancelled: { cancellation.isCancelled }, progress: progress))
            } catch {
                return .failure(PhaseSearchRefusal(reason: "\(error)"))
            }
        }.value

        guard epoch == datasetSession.epoch else {
            return .failed("The dataset changed while phase mapping was running.")
        }
        let found: StructurePhaseMapping
        switch outcome {
        case .failure(let refusal):
            let reason = "A phase's structure cannot be searched: \(refusal.reason)"
            statusText = reason
            return .failed(reason)
        case .success(nil):
            return .cancelled
        case .success(let value?):
            found = value
        }
        guard let map = PhaseMappingProduct.mapInListOrder(found.map, slotNames: slots.map(\.model.displayName),
                                                           matrixSlot: matrixSlot, candidateSlots: candidateSlots) else {
            return .failed("The phase list changed shape during the run.")
        }
        let learned = Self.learnedRelationshipLines(names: candidates.map(\.name),
                                                    relationships: found.classification.relationships)

        phaseMapping.publish(map, ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: phaseSignature,
            reference: referenceSettings,
            matching: matchSettings,
            libraryEntryCount: 0,
            matrixEntryIndex: -1,
            matrixInPlaneDegrees: .nan,
            worstChanceMatchPercent: 0,
            invAngstromPerPixel: scale.invAngstromPerPixel,
            qScaleIsPhysical: scale.provenance.isPhysical,
            peakCount: rawVectors.totalPeakCount,
            calibration: calibrationStamp,
            libraryKMaxInvAngstrom: reach,
            orientationSource: .structures,
            learnedRelationships: learned,
            excitationSlabs: zip(candidates, slabs).map { "\($0.name): " + String(format: "%.3g", $1) }
        ), structureRun: found)

        // What the run found beyond its map goes to the Output pane (control placement, rule 9).
        for line in learned { activityLog.record("Map Phases: " + line) }
        recordPhaseMappingRun(map: map, run: phaseMapping.lastRun)
        publishPhaseMapProduct()
        await publishPrecipitateClassificationFromPhaseMap()
        statusText = Self.phaseMapStatusLine(map)
        return .published
    }
}

extension AppState {
    /// One progress report of `mapFromStructures` (mac4DSTEM#333): the bar's fraction, and the stage's name in the status line. A
    /// new stage is said once through `statusText`, which the Output records, so the bar and the Output always name the same stage.
    func reportStructurePhaseMappingProgress(
        _ fraction: Double, cancellation: AnalysisCancellationToken, stages: StructurePhaseMappingStageLog
    ) {
        guard isCurrentOperation(cancellation) else { return }
        let stage = StructurePhaseMappingStage(fraction: fraction)
        if stages.enter(stage) { statusText = stage.status }
        updateCancellableOperation(cancellation, progress: fraction, status: stage.status)
    }
}

/// The stages of DiffractoKit's `mapFromStructures` by the fraction it reports (DiffractoKit 0.17.0): the matrix orientation up to 0.6,
/// its regularisation and the removal of the matrix reflections to 0.75, then the two passes, the phases' orientation search to 0.95 and
/// the variant pass to 1. Before 0.17.0 nothing came between 0.75 and 1, and the bar sat at 49,152 of 65,536 for minutes (#333).
enum StructurePhaseMappingStage: Equatable, CaseIterable {
    case matrix, refining, searching, variants

    init(fraction: Double) {
        switch fraction {
        case ..<0.6: self = .matrix
        case ..<0.75: self = .refining
        case ..<0.95: self = .searching
        default: self = .variants
        }
    }

    var status: String {
        switch self {
        case .matrix: "Finding the matrix orientation…"
        case .refining: "Refining the matrix orientations…"
        case .searching: "Searching the phases' orientations…"
        case .variants: "Classifying the phases' variants…"
        }
    }
}

/// The stage a run last named; the kit's reports arrive out of order across workers, so a stage is never named twice or named backwards.
@MainActor
final class StructurePhaseMappingStageLog: Sendable {
    private var current: StructurePhaseMappingStage?

    init(starting: StructurePhaseMappingStage? = nil) { current = starting }

    /// True when `stage` comes after the one last named (and makes it the current one).
    func enter(_ stage: StructurePhaseMappingStage) -> Bool {
        let order = StructurePhaseMappingStage.allCases
        if let current, let now = order.firstIndex(of: current), let next = order.firstIndex(of: stage), next <= now { return false }
        current = stage
        return true
    }
}
