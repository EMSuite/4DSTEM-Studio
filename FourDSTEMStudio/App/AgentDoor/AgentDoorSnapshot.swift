//
//  AgentDoorSnapshot.swift
//  Role: What a window tells an agent about itself (`Mac4DSTEMAgentDoor`): the state the person sees, as JSON, and the two pictures
//        the panes show, as PNG. Read-only: nothing here writes a property, starts a run or touches a file.
//
//  One source per fact. The result picture is `resultExportImage`, the figure File > Export writes; its record is
//  `exportedImageProvenanceRecord`, the one that figure carries. The pattern picture is the export's raster with what the pane
//  draws over it: the virtual detector in its task and, in the Disks task, the detected disks. Calibration states are the
//  readiness report's own words. So an agent judges what the person would judge, not a second rendering.
//
//  Numbers JSON cannot carry (NaN, infinity) are written as null.
//

import CoreGraphics
import Foundation
import ShellAgentDoor
import ShellEDXModel
import ShellLayout
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The recipe and the run graph it is the projection of, as the sidecar stores them.
/// A square of detector pixels an agent asks to see: centred on (x, y), `half` pixels to each side, cut to the detector.
nonisolated struct AgentPatternCrop: Equatable {
    var x: Int
    var y: Int
    var half: Int

    func rect(width: Int, height: Int) -> CGRect {
        let x0 = max(0, x - half), y0 = max(0, y - half)
        let x1 = min(width, x + half + 1), y1 = min(height, y + half + 1)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

nonisolated struct AgentLineageAnswer: Encodable {
    var recipe: [SessionReplayRecord.Step]
    var lineage: SessionLineage
}

extension AppState {

    // MARK: Pictures

    /// The diffraction pattern as the pane shows it: the export's pixels and scale bar, the virtual detector in its task and, in the
    /// Disks task, the detected disks of the pattern on screen (`agentPatternOverlays`).
    /// `disks: false` leaves the detected disks off, so a weak disk under a circle can be seen (issue #234); `crop` cuts a square of
    /// detector pixels around (x, y), which the figure then magnifies like any small pattern.
    /// `probe: true` adds the calibrated probe: a circle of the probe radius at the mean origin, so an agent can judge whether
    /// the measured radius fits the direct beam (the acceptance run, 12 Nov, had no picture of it).
    func agentPatternImage(scale: Int, disks: Bool = true, crop: AgentPatternCrop? = nil, probe: Bool = false) throws -> CGImage {
        let raster = try patternExportRaster()
        var image = raster.image
        var overlays = disks ? agentPatternOverlays : patternExportOverlays
        if probe {
            let calibration = calibrationSession.calibration
            guard let origin = calibration.meanOrigin, let radius = calibration.probeRadius else {
                throw SimpleError("There is no calibrated origin and probe radius yet; run_calibration step origin measures them.")
            }
            overlays.append(.peaks([BraggPeak(x: origin.x, y: origin.y, intensity: 1)], probeRadius: radius, exportColorScheme))
        }
        if let crop {
            let rect = crop.rect(width: image.width, height: image.height)
            guard rect.width > 0, rect.height > 0, let cut = image.cropping(to: rect) else {
                throw SimpleError("The crop lies outside the pattern (\(image.width) × \(image.height) detector pixels).")
            }
            image = cut
            overlays = Self.overlays(overlays, croppedTo: rect)
        }
        return Self.burnScaleBar(on: image, unitsPerDataPixel: raster.sampling, unitLabel: raster.unit,
                                 pixelScale: max(scale, Self.agentPatternMinimumScale), overlays: overlays)
    }

    /// The overlays of a pattern cut to `rect` (detector pixels): disks moved into the cut's coordinates, those outside it dropped.
    /// The virtual detector's outline belongs to the whole pattern and is left off a cut.
    static func overlays(_ overlays: [FigureOverlay], croppedTo rect: CGRect) -> [FigureOverlay] {
        overlays.compactMap { overlay in
            guard case .peaks(let peaks, let radius, let scheme) = overlay else { return nil }
            let inside = peaks.filter { rect.insetBy(dx: -0.5, dy: -0.5).contains(CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))) }
            return .peaks(inside.map { BraggPeak(x: $0.x - Float(rect.minX), y: $0.y - Float(rect.minY), intensity: $0.intensity) },
                          probeRadius: radius, scheme)
        }
    }

    /// The raw counts of the pattern on screen in a square around (x, y), with the brightest pixel and the box edge's median as the
    /// local background, so an agent can tell a weak disk from noise by numbers as well as by eye (issue #234).
    func agentPatternValues(x: Int, y: Int, half: Int) -> [String: Any]? {
        guard let pattern = displayedPattern, (0..<pattern.qx).contains(x), (0..<pattern.qy).contains(y) else { return nil }
        let rect = AgentPatternCrop(x: x, y: y, half: half).rect(width: pattern.qx, height: pattern.qy)
        let x0 = Int(rect.minX), y0 = Int(rect.minY), x1 = Int(rect.maxX), y1 = Int(rect.maxY)
        var rows: [[Any]] = []
        var edge: [Float] = []
        var brightest: (value: Float, x: Int, y: Int)?
        for row in y0..<y1 {
            var values: [Any] = []
            for column in x0..<x1 {
                let value = pattern.pixels[row * pattern.qx + column]
                values.append(AgentJSON.number(value))
                if value.isFinite {
                    if value > (brightest?.value ?? -.infinity) { brightest = (value, column, row) }
                    if row == y0 || row == y1 - 1 || column == x0 || column == x1 - 1 { edge.append(value) }
                }
            }
            rows.append(values)
        }
        edge.sort()
        let background: Float? = edge.isEmpty ? nil : edge[edge.count / 2]
        return [
            "scan_position": ["x": selectedScan.x, "y": selectedScan.y],
            "shown": patternDisplayMode.rawValue,
            "box": ["x0": x0, "y0": y0, "width": x1 - x0, "height": y1 - y0],
            "values": rows,
            "values_order": "rows from y0 down, each from x0 to the right; raw counts as stored, not the display's log or range",
            "brightest": brightest.map { ["x": $0.x, "y": $0.y, "value": AgentJSON.number($0.value)] as [String: Any] } ?? NSNull(),
            "edge_median": AgentJSON.number(background),
            "pattern_maximum": AgentJSON.number(pattern.minMax.1),
        ]
    }

    /// The pattern picture has at least a Retina screen's two pixels per point, because the pane is seen that way. At one pixel per
    /// point the 1.2 pt rings of the detected disks blur into the disks' own colour, and an agent can miss them (#185).
    static let agentPatternMinimumScale = 2

    /// What the diffraction pane strokes over the pattern, under the pane's own conditions (`UI/ImagePanes.swift`).
    var agentPatternOverlays: [FigureOverlay] {
        var overlays = patternExportOverlays
        if navigation.analysisMode == .disks, !currentPeaks.isEmpty {
            overlays.append(.peaks(currentPeaks, probeRadius: probeKernel?.probeRadius, exportColorScheme))
        }
        return overlays
    }

    // MARK: The window in one line

    /// The door adds the window's `id`.
    func agentSummary() -> [String: Any] {
        [
            "file_name": AgentJSON.orNull(descriptor?.fileName),
            "has_4d_dataset": hasDataset,
            "has_spectrum_image": hasSpectrumImage,
            "workspace": navigation.workspaceArea.title,
            "task": navigation.analysisMode.rawValue,
            "busy": agentBusy,
            "status": statusText,
        ]
    }

    /// Busy as an agent must read it, the same in list_windows and get_window (#266, #323): an operation, an open in flight
    /// (its whole-cube pass included, which runs outside the operation center), an open the door started that has not begun
    /// yet, or the EDS room at work.
    var agentBusy: Bool {
        isBusy || datasetSession.isLoading || edx.isBusy || openInFlight
    }

    // MARK: The window in full

    func agentSnapshot() -> [String: Any] {
        var snapshot = agentSummary()
        snapshot["dataset"] = agentDataset
        snapshot["calibration"] = agentCalibration
        snapshot["view"] = [
            "workspace": navigation.workspaceArea.title,
            "workspace_id": navigation.workspaceArea.rawValue,
            "task": navigation.analysisMode.rawValue,
            "scan_position": ["x": selectedScan.x, "y": selectedScan.y],
            "pattern_shown": patternDisplayMode.rawValue,
            "task_settings": AgentJSON.orNull(agentTaskSettings),
            "display": agentDisplay,
        ] as [String: Any]
        snapshot["operation"] = [
            "busy": agentBusy,
            "name": AgentJSON.orNull(activeOperation ?? (datasetSession.isLoading || openInFlight ? "Opening" : nil)),
            "progress": AgentJSON.number(progress),
            "status": statusText,
            "error": AgentJSON.orNull(errorMessage ?? lastComputeFailure),
            // The last export the door started (#514): writing, written, failed with its error, or cancelled.
            "last_export": AgentJSON.orNull(agentLastExport?.json),
            // The last run the door started (#330): a script waits for finished_run_id to reach the run_id its call answered.
            "last_run": AgentJSON.orNull(agentLastRun?.json),
            "finished_run_id": AgentJSON.orNull(agentFinishedRunID),
        ] as [String: Any]
        snapshot["result"] = agentResult
        snapshot["pattern"] = agentPattern
        snapshot["disk_detection"] = agentDiskDetection
        snapshot["session"] = agentSession
        snapshot["has_precipitate_objects"] = precipitateObjectReport != nil
        if let pending = promotionRun.pendingLoad, pending.preprocess == nil {
            var open = Mac4DSTEMAgentDoor.reductionSummary(pending.configuration)
            open["file"] = pending.url.lastPathComponent
            open["preview_ready"] = pending.preview != nil
            open["refusal"] = AgentJSON.orNull(pending.directBeamRefusal ?? pending.refusalReason)
            snapshot["pending_open"] = open
        } else {
            snapshot["pending_open"] = NSNull()
        }
        snapshot["log_tail"] = Array(activityLog.messages.suffix(20))
        return snapshot
    }

    /// The current task's settings: its replay signature, which is what the run records; for the two tasks whose staleness is
    /// judged without one (Phase mapping, Diffraction groups) the settings themselves (issue #209).
    private var agentTaskSettings: Any? {
        switch navigation.analysisMode {
        case .phaseMapping:
            return Mac4DSTEMAgentDoor.phaseMappingSettings(of: self)["phase_mapping"]
        case .diffractionGroups:
            let settings = diffractionGroups.settings
            return ["binned_size": settings.binnedSize, "components": settings.components, "groups": settings.groups,
                    "seed": settings.seed] as [String: Any]
        default:
            return settingsReplaySignature(for: navigation.analysisMode)
        }
    }

    private var agentDataset: Any {
        guard let descriptor else { return NSNull() }
        return [
            "file_name": descriptor.fileName,
            "file_path": descriptor.filePath,
            "dataset_path": descriptor.datasetPath,
            "source_shape": descriptor.shape,
            "source_shape_order": descriptor.is4D ? "scan rows, scan columns, detector rows, detector columns" : "as stored",
            "dtype": descriptor.dtypeDescription,
            "loaded_view": loadedView.summary ?? "whole file",
            "binning_notice": AgentJSON.orNull(loadedView.binningNotice),
        ] as [String: Any]
    }

    var agentCalibration: [String: Any] {
        let calibration = calibrationSession.calibration
        let verdict = calibrationSession.verdict
        var out: [String: Any] = [
            "quantitative": verdict.quantitative,
            "verdict": verdict.summary,
            // The readiness report in the door's locale: its details are the checklist's, with a point (issue #233; a German Mac
            // gave "0,01904" beside the JSON's 0.01904).
            "items": CalibrationReadinessReport.make(calibration: calibration, provenance: calibrationSession.provenance,
                                                     convergenceSemiAngleMrad: calibrationSession.convergenceSemiAngleMrad,
                                                     voltageKV: calibrationSession.acceleratingVoltage,
                                                     locale: Mac4DSTEMAgentDoor.textLocale).items.map { item in
                // "flag": what the row's own check flagged (#511), so a scattered centre of mass never reads as measured.
                ["item": item.kind.rawValue, "state": item.stateText, "ready": item.status.isReady, "detail": item.detail,
                 "flag": AgentJSON.orNull(item.flag)] as [String: Any]
            },
            "q_pixel_size": AgentJSON.number(calibration.qPixelSize),
            "q_pixel_units": AgentJSON.orNull(calibration.qPixelUnits),
            "r_pixel_size": AgentJSON.number(calibration.rPixelSize),
            "r_pixel_units": AgentJSON.orNull(calibration.rPixelUnits),
            "qr_rotation_deg": AgentJSON.number(calibration.rotationRad.map { RQRotationConvention.displayDegrees(fromApp: $0) }),   // py4DSTEM's sign, as the screen and the log (ADR 040)
            "qr_flip": calibration.rotationRad == nil ? NSNull() : (calibration.transposeQR ?? false) as Any,   // py4DSTEM's QR_flip (#275)
            "probe_radius_px": AgentJSON.number(calibration.probeRadius),
            "accelerating_voltage_kv": AgentJSON.number(calibrationSession.acceleratingVoltage),
            "convergence_semiangle_mrad": AgentJSON.number(calibrationSession.convergenceSemiAngleMrad),
            // The probe radius the optics imply (#511); null until the convergence angle, voltage and Q scale are all known.
            "expected_probe_radius_px": AgentJSON.number(CalibrationReadinessReport.expectedProbeRadiusPixels(
                convergenceSemiAngleMrad: calibrationSession.convergenceSemiAngleMrad,
                voltageKV: calibrationSession.acceleratingVoltage, calibration: calibration)),
        ]
        if let origin = calibration.meanOrigin {
            out["mean_origin_px"] = ["x": AgentJSON.number(origin.x), "y": AgentJSON.number(origin.y)]
        } else {
            out["mean_origin_px"] = NSNull()
        }
        out["spot_distortion_fit"] = AgentJSON.orNull(spotDistortion.pending?.summary(locale: Mac4DSTEMAgentDoor.textLocale))
        // How the origin in force was measured and how well its per-position fit holds (#330): the status line's "fit RMS"
        // as a number, so a script reads it without parsing text.
        out["origin_fit_rms_px"] = AgentJSON.number(calibration.origin?.rmsResidual)
        out["origin_method"] = agentOriginMethod
        return out
    }

    /// centre_of_mass, friedel, bragg_peaks or manual from the active origin run; the file's or session's origin otherwise.
    var agentOriginMethod: Any {
        let run = replay.lineage.activeNodes().last { $0.kind == "calibration_origin" }?.parameters["method"]
        switch run {
        case OriginMethod.centreOfMass.rawValue?: return "centre_of_mass"
        case OriginMethod.friedel.rawValue?: return "friedel"
        case "bragg_peaks"?, "manual"?, "restored"?: return run!
        default:
            switch calibrationSession.calibration.originProvenance {
            case .geometricDefault: return NSNull()
            case .fileMean, .fileMaps: return "file"
            case .sessionMean, .sessionMaps: return "session"
            case .manual: return "manual"
            case .fitted: return "fitted"
            }
        }
    }

    private var agentResult: Any {
        guard let product = displayedProduct else { return NSNull() }
        var out: [String: Any] = [
            "kind": product.kind,
            "name": product.displayName,
            "width": product.width,
            "height": product.height,
            "domain": product.domain.rawValue,
            "quantitative_status": product.quantitativeStatus.rawValue,
            "value_units": product.valueUnits,
            "pixel_size_row": AgentJSON.number(product.sampling.row),
            "pixel_size_column": AgentJSON.number(product.sampling.column),
            "pixel_units": AgentJSON.orNull(product.sampling.units),
            "provenance": product.provenance,
            "caption": publicationCaption,
            "image": "get_result_image",
        ]
        if let range = resultDisplayedValueRange {
            out["display_range"] = ["low": AgentJSON.number(range.low), "high": AgentJSON.number(range.high)]
        }
        out["statistics"] = Self.agentStatistics(of: product)
        return out
    }

    /// The displayed result's numbers over its valid finite pixels (#330): count, mean, standard deviation (population, as
    /// numpy's default ddof 0), min and max, so a script checks a map without fetching it. Null for a colour (rgba) result.
    nonisolated static func agentStatistics(of product: DisplayedProduct) -> Any {
        guard case .scalar(let image) = product.payload else { return NSNull() }
        var count = 0, sum = 0.0, low = Double.infinity, high = -Double.infinity
        for (index, value) in image.pixels.enumerated() where value.isFinite
            && (index >= product.validityMask.count || product.validityMask[index]) {
            let v = Double(value)
            count += 1; sum += v; low = min(low, v); high = max(high, v)
        }
        guard count > 0 else {
            return ["count_finite": 0, "mean": NSNull(), "std": NSNull(), "min": NSNull(), "max": NSNull()] as [String: Any]
        }
        let mean = sum / Double(count)
        var squares = 0.0
        for (index, value) in image.pixels.enumerated() where value.isFinite
            && (index >= product.validityMask.count || product.validityMask[index]) {
            let d = Double(value) - mean
            squares += d * d
        }
        return ["count_finite": count, "mean": mean, "std": (squares / Double(count)).squareRoot(),
                "min": low, "max": high] as [String: Any]
    }

    /// Whether the pattern on screen, and in the Disks task its detected disks, belong to the scan position selected (#330):
    /// select_scan_position answers before the pattern loads and the live detection runs.
    var agentPatternReady: Bool {
        let patternIn = patternDisplayMode != .current || currentPatternScan == selectedScan
        let detecting = diskDetection.liveDetectionInFlight || diskDetection.liveDetectionPending
        let disksIn = navigation.analysisMode != .disks || probeKernel == nil || detectedPatternScan == currentPatternScan
        return patternIn && !detecting && disksIn
    }

    private var agentPattern: Any {
        guard let pattern = displayedPattern else { return NSNull() }
        return [
            "width": pattern.qx,
            "height": pattern.qy,
            "ready": agentPatternReady,
            "shown": patternDisplayMode.rawValue,
            "log_scale": logScale,
            "image": "get_pattern_image",
        ] as [String: Any]
    }

    private var agentDiskDetection: [String: Any] {
        let params = diskDetection.diskParams
        var out: [String: Any] = [
            "parameters": [
                "corr_power": AgentJSON.number(params.corrPower),
                "sigma_dp": AgentJSON.number(params.sigmaDP),
                "sigma_cc": AgentJSON.number(params.sigmaCC),
                "subpixel": params.subpixel.provenanceID,   // pixel, poly, multicorr: the recipe's names (task_settings)
                "upsample_factor": params.upsampleFactor,
                "min_absolute_intensity": AgentJSON.number(params.minAbsoluteIntensity),
                "min_relative_intensity": AgentJSON.number(params.minRelativeIntensity),
                "relative_to_peak": params.relativeToPeak,
                "min_peak_spacing": AgentJSON.number(params.minPeakSpacing),
                "edge_boundary": params.edgeBoundary,
                "max_num_peaks": params.maxNumPeaks,
            ] as [String: Any],
            "probe_radius_px": AgentJSON.number(probeKernel?.probeRadius),
            "validation_issues": diskDetectionValidationIssues.map(\.message),
            "current_pattern_disk_count": currentPeaks.count,
            "has_current_bragg_vectors": hasCurrentBraggVectors,
            "settings_changed_since_run": diskDetectionSettingsAreStale,
        ]
        if let diagnostics = currentDiskDiagnostics {
            out["current_pattern"] = [
                "local_maxima": diagnostics.localMaximumCount,
                "after_absolute_threshold": diagnostics.afterAbsoluteThresholdCount,
                "after_relative_threshold": diagnostics.afterRelativeThresholdCount,
                "after_spacing": diagnostics.afterSpacingCount,
                "accepted": diagnostics.acceptedCount,
                "count_limited": diagnostics.wasCountLimited,
                "correlation_maximum": AgentJSON.number(diagnostics.correlationMaximum),
                "non_finite_pixels": diagnostics.nonFinitePixelCount,
                "failure": AgentJSON.orNull(diagnostics.detectionFailure),
            ] as [String: Any]
        }
        out["scan_summary"] = NSNull()   // said, not left out: no whole-scan detection has finished, or the last was cancelled (#266)
        if let summary = completedDiskSummary {
            out["scan_summary"] = [
                "positions": summary.positionCount,
                "total_disks": summary.totalPeakCount,
                "minimum_per_position": summary.minimumPeakCount,
                "median_per_position": AgentJSON.number(summary.medianPeakCount),
                "maximum_per_position": summary.maximumPeakCount,
                "positions_without_disks": summary.zeroPeakPositionCount,
                "positions_at_the_maximum": summary.atMaximumPositionCount,
                "positions_failed": summary.failedPositionCount,
                "warnings": summary.warnings,
            ] as [String: Any]
        }
        return out
    }

    private var agentSession: [String: Any] {
        [
            "has_sidecar": sessionInventory.hasSidecar,
            // A session file that exists but could not be read is not "no sidecar" (issue #233; the sandbox refused one).
            "sidecar_unreadable": AgentJSON.orNull(sessionSidecar.unreadableReason),
            "has_bragg_vectors": sessionInventory.hasBraggVectors,
            "has_calibration": sessionInventory.hasCalibration,
            "saved_results": sessionInventory.results.map { saved in
                ["id": saved.id, "kind": saved.kind, "name": saved.displayName, "width": saved.width, "height": saved.height,
                 "value_units": saved.valueUnits, "provenance": saved.provenance] as [String: Any]
            },
            "recipe_steps": replay.record.steps.map(\.kind),
        ]
    }

    // MARK: Lists

    /// The detected disks of the pattern on screen, in the pattern's own pixels.
    var agentPeaks: [String: Any] {
        [
            "scan_position": ["x": selectedScan.x, "y": selectedScan.y],
            // The position the disks below were detected on, and whether that is the one selected with the detection done (#330).
            "pattern_scan_position": AgentJSON.orNull(detectedPatternScan.map { ["x": $0.x, "y": $0.y] }),
            "ready": agentPatternReady,
            "coordinates": "detector pixels of the pattern as shown: x to the right, y down, (0, 0) the centre of the top-left pixel",
            "probe_radius_px": AgentJSON.number(probeKernel?.probeRadius),
            "disks": currentPeaks.map { peak in
                ["x": AgentJSON.number(peak.x), "y": AgentJSON.number(peak.y), "intensity": AgentJSON.number(peak.intensity)]
            },
        ]
    }

    var agentLineage: AgentLineageAnswer {
        AgentLineageAnswer(recipe: replay.record.steps, lineage: replay.lineage)
    }
}
