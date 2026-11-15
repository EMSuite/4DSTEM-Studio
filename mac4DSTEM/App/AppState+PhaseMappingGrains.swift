//
//  AppState+PhaseMappingGrains.swift
//  Role: Map Phases, "Grains and phases (no matrix)" (mac4DSTEM#252): every position matched against each phase's template
//        library, the best phase per position with ASTAR's phase reliability (Rauch & Dupuy, Arch. Metall. Mater. 50 (2005) 87;
//        the template matching after Ophus et al., Microsc. Microanal. 28 (2022) 390). The numerics are DiffractoKit's
//        (`PhaseOrientationCandidate`, `matrixOrientations`, `BestPhaseMatching`); `GrainsPhaseRun.run` composes them and this
//        file hands it its inputs and publishes what it returns.
//

import ShellLayout
import Foundation
#if canImport(DSTEMCore)
import DiffractoCore
import DSTEMCore
import DSTEMSession
#endif
import DiffractoOrientation

extension AppState {

    /// Map Phases, grains and phases. Called by `runPhaseMapping` after its refusals (stale disks, the list's own refusal, no
    /// disks, no physical Q scale), so none of them is repeated here.
    func runPhaseMappingGrains() async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("Open a dataset first.") }
        guard let rawVectors = resultPresentation.braggVectors else { return .failed("Detect Bragg disks first.") }
        let slots = phaseMapping.phases
        guard slots.count >= 2 else { return .failed("Add at least two phases.") }

        let referenceSettings = phaseMapping.reference
        let matchSettings = phaseMapping.matching
        let phaseSignature = phaseMapping.phaseSignature
        let calibrated = calibratedBraggVectors(rawVectors, descriptor: descriptor)
        let origin = calibrated.origin.point
        // The reach and the peak cut are the structures run's: the nearest detector edge, at most Max |q|.
        let reach = phaseLibraryKMax(setting: referenceSettings.kMaxInvAngstrom, origin: origin, descriptor: descriptor)
        let cut = Self.matchingWithinLibraryReach(matchSettings, libraryKMaxInvAngstrom: reach).maximumVectorInvAngstrom
        let beam = matchSettings.directBeamRadiusInvAngstrom
        let phases = slots.map { (name: $0.model.displayName, crystal: $0.model.structure) }
        let calibrationStamp = PhaseMappingProduct.CalibrationStamp(
            calibration: calibrationSession.calibration, referenceOrigin: origin)
        let scale = acomScaleSemantics
        let invAngstromPerPixel = scale.invAngstromPerPixel

        let status = "Matching every phase's templates…"
        let cancellation = beginCancellableOperation("Phase mapping", status: status,
                                                     totalUnits: calibrated.vectors.peaks.count)
        defer { finishCancellableOperation(cancellation) }
        let epoch = datasetSession.epoch
        let progress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentOperation(cancellation) else { return }
                self.updateCancellableOperation(cancellation, progress: fraction, status: status)
            }
        }
        let scan = calibrated.vectors.phaseScan
        let scanWidth = calibrated.vectors.scanWidth, scanHeight = calibrated.vectors.scanHeight
        let outcome: Result<GrainsPhaseRun?, GrainsPhaseRun.Refusal> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try GrainsPhaseRun.run(
                    scan: scan, scanWidth: scanWidth, scanHeight: scanHeight, phases: phases,
                    reachInvAngstrom: reach, maximumVectorInvAngstrom: cut, directBeamRadiusInvAngstrom: beam,
                    originX: origin.x, originY: origin.y, invAngstromPerPixel: invAngstromPerPixel,
                    isCancelled: { cancellation.isCancelled }, progress: progress))
            } catch let refusal as GrainsPhaseRun.Refusal {
                return .failure(refusal)
            } catch {
                return .failure(GrainsPhaseRun.Refusal(reason: "\(error)"))
            }
        }.value

        guard epoch == datasetSession.epoch else {
            return .failed("The dataset changed while phase mapping was running.")
        }
        let found: GrainsPhaseRun
        switch outcome {
        case .failure(let refusal):
            let reason = "A phase's structure cannot be matched: \(refusal.reason)"
            statusText = reason
            return .failed(reason)
        case .success(nil):
            return .cancelled
        case .success(let value?):
            found = value
        }

        phaseMapping.publish(grains: found, ranWith: PhaseMappingProduct.RunRecord(
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
            orientationSource: .grains))
        guard let map = phaseMapping.map else { return .failed("The run published no map.") }
        recordPhaseMappingRun(map: map, run: phaseMapping.lastRun)
        publishPhaseMapProduct()
        // No matrix, so no precipitates: the objects of an earlier matrix run do not stay beside this map.
        precipitateClassification.clear()
        statusText = grainsStatusLine ?? Self.phaseMapStatusLine(map)
        return .published
    }

    /// The status line of a grains map: each phase's positions and the unsure ones, at the current threshold.
    var grainsStatusLine: String? {
        guard let run = phaseMapping.lastGrainsRun else { return nil }
        let threshold = phaseMapping.grainsReliableAbove
        let counts = run.counts(reliableAbove: threshold)
        func n(_ value: Int) -> String { CalibrationUnitConversion.displayCount(value, locale: .autoupdatingCurrent) }
        let phases = zip(run.phaseNames, counts.perPhase).map { "\($0) \(n($1))" }.joined(separator: ", ")
        let noPeaks = run.usablePeakCounts.reduce(0) { $0 + ($1 == 0 ? 1 : 0) }
        return "Phase map: \(phases), unsure (reliability below \(Num.fixed(threshold, 0))) \(n(counts.unsure))"
            + (noPeaks > 0 ? ", no peaks \(n(noPeaks))" : "")
    }

    /// The reliability map of a grains run (#252): every position with a winner at ASTAR's reliability, 0 to 100.
    func publishPhaseReliabilityProduct() {
        guard let map = phaseMapping.map, let run = phaseMapping.lastRun, let field = phaseOrientationField,
              let image = field.reliabilityImage(), let validity = field.reliabilityValidity() else { return }
        let own = scanMapPersistenceMetadata(for: .phaseMapping)
        var extra = phaseProvenance(map: map, run: run)
        extra["quantitative_status"] = "relative"
        publishProduct(
            kind: PhaseResultPicture.reliability.productKind,
            displayName: PhaseMappingProduct.reliabilityDisplayName,
            valueUnits: "reliability",
            payload: .scalar(image),
            validityMask: validity,
            domain: .scan,
            sampling: ProductSampling(row: own.row, column: own.column, units: own.units),
            extraProvenance: own.provenance.merging(extra) { _, new in new },
            ownProvenanceOnly: true
        )
    }

    /// The grains threshold moved: the map was read again from the held run (`PhaseMappingProduct.grainsReliableAbove`), so the
    /// picture on screen, the status line and the lineage follow it.
    func grainsReliabilityDidChange() {
        guard phaseMapping.lastGrainsRun != nil, phaseMapping.map != nil else { return }
        if let line = grainsStatusLine { statusText = line }
        if let shown = PhaseResultPicture(productKind: displayedProduct?.kind) { showPhaseResult(shown) }
    }
}
