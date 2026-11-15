//
//  CraftedSidecarInputTests.swift
//  mac4DSTEM#300: a crafted session sidecar (its JSON crop, its stored RGBA pixels) is refused or clipped, never a trap.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class CraftedSidecarInputTests: XCTestCase {

    /// Mutation: `fits` back to `yOffset + self.height <= height` - the first crop traps on overflow, red (a crash).
    func testACropWhoseEdgeOverflowsDoesNotFitAndIsRefused() throws {
        let crafted = AxisCrop(yOffset: Int.max - 1, xOffset: 0, height: 10, width: 4)
        XCTAssertFalse(crafted.fits(height: 64, width: 64))
        XCTAssertFalse(AxisCrop(yOffset: 0, xOffset: Int.max, height: 4, width: Int.max).fits(height: 64, width: 64))
        XCTAssertTrue(AxisCrop(yOffset: 60, xOffset: 0, height: 4, width: 64).fits(height: 64, width: 64))
        XCTAssertFalse(AxisCrop(yOffset: 61, xOffset: 0, height: 4, width: 64).fits(height: 64, width: 64))

        let source = DatasetDescriptor(filePath: "/nonexistent/crafted.h5", datasetPath: "/data",
                                       shape: [64, 64, 8, 8], dtypeDescription: "uint16", chunkShape: nil)
        XCTAssertThrowsError(try LoadView(source: source, specification: LoadSpecification(scanCrop: crafted))) { error in
            guard case LoadSpecificationError.scanCropOutOfBounds = error else { return XCTFail("refused as \(error)") }
        }
    }

    /// Mutation: the NaN branch removed - `UInt8(NaN)` traps, red (a crash).
    func testStoredRGBASamplesClipAndANaNReadsAsZero() {
        XCTAssertEqual(BraggVectorEMDWriter.rgbaBytes(fromStored: [.nan, -3, 0.9, 127.6, 255, 1e9, .infinity, -.infinity]),
                       [0, 0, 0, 127, 255, 255, 255, 0])
    }
}
