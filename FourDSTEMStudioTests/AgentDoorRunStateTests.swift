//
//  AgentDoorRunStateTests.swift
//  #330: what a script needs to drive the agent door without guessing: each run's id and when it finished, whether the pattern
//  and its disks belong to the scan position selected, the origin fit's RMS and method, and the displayed result's numbers.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorRunStateTests: XCTestCase {
    private func operation(_ state: AppState) throws -> [String: Any] {
        try XCTUnwrap(state.agentSnapshot()["operation"] as? [String: Any])
    }

    private func waitForRun(_ state: AppState, _ id: Int) async throws {
        for _ in 0..<500 where (state.agentFinishedRunID ?? 0) < id { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThanOrEqual(state.agentFinishedRunID ?? 0, id, "run \(id) did not finish")
    }

    /// A run answers its id at once; last_run says running, then finished with the status line and the disk settings it moved.
    /// Mutation: finished_run_id set when the run starts - red at the first assertion.
    func testARunSaysWhenItFinishedAndWhatItChanged() async throws {
        let state = AppState()
        let spacing = state.diskDetection.diskParams.minPeakSpacing
        let id = state.agentRun("test_run") {
            try? await Task.sleep(for: .milliseconds(50))
            state.diskDetection.diskParams.minPeakSpacing = spacing + 3
            state.statusText = "done here"
        }
        XCTAssertNil(state.agentFinishedRunID, "nothing has finished yet")
        var last = try XCTUnwrap(try operation(state)["last_run"] as? [String: Any])
        XCTAssertEqual(last["run_id"] as? Int, id)
        XCTAssertEqual(last["state"] as? String, "running")

        try await waitForRun(state, id)
        let op = try operation(state)
        XCTAssertEqual(op["finished_run_id"] as? Int, id)
        last = try XCTUnwrap(op["last_run"] as? [String: Any])
        XCTAssertEqual(last["state"] as? String, "finished")
        XCTAssertEqual(last["status_line"] as? String, "done here")
        XCTAssertTrue(last["error"] is NSNull)
        let changed = try XCTUnwrap(last["changed_disk_settings"] as? [String: [String: Double]])
        XCTAssertEqual(changed["min_peak_spacing"]?["to"], Double(spacing + 3))
        XCTAssertEqual(changed.count, 1, "only the setting that moved")

        let next = state.agentRun("second") {}
        XCTAssertEqual(next, id + 1)
    }

    /// A run whose step fails after it started reports failed and the error. Mutation: state from `finished` alone - red.
    func testAFailedRunSaysFailed() async throws {
        let state = AppState()
        let id = state.agentRun("failing") { state.presentComputeFailure(SimpleError("The fit did not converge.")) }
        try await waitForRun(state, id)
        let last = try XCTUnwrap(try operation(state)["last_run"] as? [String: Any])
        XCTAssertEqual(last["state"] as? String, "failed")
        XCTAssertTrue((last["error"] as? String ?? "").contains("did not converge"), "\(last)")
    }

    /// Selecting a position is not ready until its pattern is read; then it is. Mutation: ready true always - red.
    func testThePatternIsReadyOnlyOnceItBelongsToTheSelectedPosition() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let descriptor = try XCTUnwrap(state.descriptor, state.statusText)
        XCTAssertGreaterThan(descriptor.rx, 1)
        state.patternDisplayMode = .current
        await state.loadCurrentPattern()
        XCTAssertTrue(state.agentPatternReady, "the pattern of the selected position is on screen")

        state.selectedScan = ScanPos(x: 1, y: 0)   // as selectScan does, before its load lands
        XCTAssertFalse(state.agentPatternReady)
        XCTAssertEqual(state.agentPeaks["ready"] as? Bool, false)
        await state.loadCurrentPattern()
        XCTAssertTrue(state.agentPatternReady)
        let peaks = state.agentPeaks
        XCTAssertEqual(peaks["ready"] as? Bool, true)
        XCTAssertEqual((peaks["pattern_scan_position"] as? [String: Int])?["x"], 1)
    }

    /// The origin's method and fit RMS are numbers in get_window's calibration. Mutation: origin_method left out - red.
    func testTheOriginSaysHowItWasMeasuredAndItsFitRMS() async throws {
        let state = AppState()
        await state.openDemoFixture()
        await state.calibrateOrigin()
        let calibration = state.agentCalibration
        XCTAssertEqual(calibration["origin_method"] as? String, "centre_of_mass", state.statusText)
        let rms = try XCTUnwrap(calibration["origin_fit_rms_px"] as? Double, "\(calibration["origin_fit_rms_px"] ?? "nil")")
        XCTAssertEqual(rms, Double(try XCTUnwrap(state.calibrationSession.calibration.origin?.rmsResidual)), accuracy: 1e-6)
    }

    /// The result's statistics are over valid finite pixels, std with ddof 0 (numpy's default). Mutation: the mask ignored - red.
    func testResultStatisticsAreOverValidFinitePixels() throws {
        let image = FloatImage(width: 3, height: 2, pixels: [1, 2, 3, .nan, 100, 5])
        let product = DisplayedProduct(kind: "test", displayName: "Test", payload: .scalar(image), domain: .scan,
                                       validityMask: [true, true, true, true, false, true],
                                       sampling: ProductSampling(row: nil, column: nil, units: nil),
                                       valueUnits: "a.u.", quantitativeStatus: .relative)
        let stats = try XCTUnwrap(AppState.agentStatistics(of: product) as? [String: Any])
        XCTAssertEqual(stats["count_finite"] as? Int, 4)
        XCTAssertEqual(try XCTUnwrap(stats["mean"] as? Double), 2.75, accuracy: 1e-12)
        // numpy.std([1, 2, 3, 5]) = 1.479019945774904
        XCTAssertEqual(try XCTUnwrap(stats["std"] as? Double), 1.479019945774904, accuracy: 1e-12)
        XCTAssertEqual(stats["min"] as? Double, 1)
        XCTAssertEqual(stats["max"] as? Double, 5)

        let colour = DisplayedProduct(kind: "rgb", displayName: "RGB", payload: .rgba(RGBAImage(width: 1, height: 1, rgba: [0, 0, 0, 255])),
                                      domain: .scan, sampling: ProductSampling(row: nil, column: nil, units: nil),
                                      valueUnits: "", quantitativeStatus: .categorical)
        XCTAssertTrue(AppState.agentStatistics(of: colour) is NSNull)
    }
}
