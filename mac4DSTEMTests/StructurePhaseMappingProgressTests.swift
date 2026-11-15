//
//  StructurePhaseMappingProgressTests.swift
//  mac4DSTEM#333: phase mapping from structures shows each of the kit's stages in the bar and the Output alike, and the kit's
//  progress moves through its two passes instead of sitting at 0.75 (49,152 of 65,536) for minutes.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class StructurePhaseMappingProgressTests: XCTestCase {

    /// Mutation: a boundary moved (say the search starting at 0.6 as before) - red.
    func testEachFractionNamesTheKitsStage() {
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 0), .matrix)
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 0.59), .matrix)
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 0.6), .refining)
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 0.749), .refining)
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 0.75), .searching)
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 0.94), .searching)
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 0.95), .variants)
        XCTAssertEqual(StructurePhaseMappingStage(fraction: 1), .variants)
        XCTAssertEqual(Set(StructurePhaseMappingStage.allCases.map(\.status)).count, 4, "four stages, four names")
    }

    /// The status line and the Output name the same stage, each stage once and in order, even when the kit's workers report out of
    /// order. Mutation: the status set only as a readout (as before #333) - the Output never names the later stages, red.
    func testTheStatusLineAndTheOutputNameTheSameStage() {
        let state = AppState()
        let token = state.beginCancellableOperation("Phase mapping", status: StructurePhaseMappingStage.matrix.status, totalUnits: 65_536)
        defer { state.finishCancellableOperation(token) }
        let stages = StructurePhaseMappingStageLog(starting: .matrix)
        let before = state.activityLog.messages.count
        for fraction in [0.1, 0.55, 0.65, 0.72, 0.76, 0.9, 0.74, 0.96, 0.99, 1.0] {
            state.reportStructurePhaseMappingProgress(fraction, cancellation: token, stages: stages)
        }
        // An Output line is "HH:MM:SS  message".
        let logged = state.activityLog.messages.dropFirst(before).map { line in
            StructurePhaseMappingStage.allCases.first { line.hasSuffix($0.status) }?.status ?? line
        }
        XCTAssertEqual(logged, [StructurePhaseMappingStage.refining.status, StructurePhaseMappingStage.searching.status,
                                StructurePhaseMappingStage.variants.status])
        XCTAssertEqual(state.statusText, StructurePhaseMappingStage.variants.status)
    }
}
