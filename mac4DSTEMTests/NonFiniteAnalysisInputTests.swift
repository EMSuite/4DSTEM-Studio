//
//  NonFiniteAnalysisInputTests.swift
//  mac4DSTEM#300: NaN, infinite, empty or out-of-range data in the analyses and the Quick Look rendering is refused or drawn black,
//  never a trap. Each test feeds the bad input on its own; on the code before #300 each one crashed the test process.
//

import XCTest
import DSTEMCore
import FormatoPeek
import DSTEMQuickLook
@testable import mac4DSTEM

final class NonFiniteAnalysisInputTests: XCTestCase {

    /// A NaN centre of mass is drawn black and the others keep their colours; an empty scan draws nothing.
    /// Mutation: the finite guard removed - `Int(h6)` traps on the NaN hue.
    func testTheDPCColourWheelDrawsANaNCentreOfMassBlack() {
        let com: [Float] = [1, 0, .nan, .nan, 0, 1, .infinity, 2]
        let image = DPC.colorWheelRGBA(com: com, width: 2, height: 2)
        XCTAssertEqual(Array(image.rgba[4..<8]), [0, 0, 0, 255], "the NaN position")
        XCTAssertEqual(Array(image.rgba[12..<16]), [0, 0, 0, 255], "the infinite position")
        XCTAssertNotEqual(Array(image.rgba[0..<3]), [0, 0, 0], "a finite position keeps its colour")
        XCTAssertEqual(DPC.colorWheelRGBA(com: [], width: 0, height: 0).rgba, [], "an empty scan")
        XCTAssertTrue(DPC.hsvToRGB(h: .nan, s: 1, v: 1) == (0, 0, 0))
    }

    /// Mutation: the shift check removed - `Int(NaN)` traps.
    func testANaNParallaxShiftIsARefusal() throws {
        let fine = try ParallaxAligner.wholeMedianShift([.init(row: 1.4, column: -2.6), .init(row: 2, column: -3), .init(row: 2.2, column: -3.1)])
        XCTAssertEqual(fine.row, 2); XCTAssertEqual(fine.column, -3)
        XCTAssertThrowsError(try ParallaxAligner.wholeMedianShift([.init(row: .nan, column: 0), .init(row: 1, column: 1)]))
        XCTAssertThrowsError(try ParallaxAligner.wholeMedianShift([.init(row: 1, column: .infinity)]))
    }

    /// Mutation: the size guard removed - `[Float](repeating:count:)` traps on the negative crop.
    func testAPaddingThatLeavesNoImageIsARefusal() throws {
        let image = [Float](repeating: 1, count: 4 * 4)
        XCTAssertThrowsError(try ParallaxSubpixelReconstructor.crop(image, width: 4, height: 4, paddingY: 4, paddingX: 0, factor: 2))
        let kept = try ParallaxSubpixelReconstructor.crop(image, width: 4, height: 4, paddingY: 1, paddingX: 1, factor: 2)
        XCTAssertEqual(kept.width, 2); XCTAssertEqual(kept.height, 2)
    }

    /// Mutation: the order clamp removed - `-maxOrder...maxOrder` traps on a negative order.
    func testANegativeStrainOverlayOrderDrawsNoReflections() throws {
        let map = try XCTUnwrap(StrainFrameTests.syntheticStrainMap())
        let overlay = try XCTUnwrap(FitOverlays.strainOverlay(map: map, scanIndex: 2, calibration: Calibration(),
                                                              referenceOrigin: (x: 64, y: 64), patternWidth: 128, patternHeight: 128,
                                                              maxOrder: -1))
        XCTAssertTrue(overlay.predicted.isEmpty)
    }

    /// Data at ±Float.greatestFiniteMagnitude: the stretch's span overflowed Float. Mutation: the Float arithmetic back - `UInt8(NaN)`.
    func testQuickLookDrawsDataAtTheFloatLimits() {
        let extreme = Float.greatestFiniteMagnitude
        let pixels: [Float] = (0..<64).map { $0.isMultiple(of: 2) ? extreme : -extreme }
        let frame = Peek.Frame(width: 8, height: 8, pixels: pixels, sourceWidth: 8, sourceHeight: 8, stride: 1,
                               kind: .image, enteredAt: [], source: "planted")
        let grey = QuickLookRendering.grayscale(frame)
        XCTAssertEqual(grey.count, 64)
        XCTAssertEqual(grey[0], 255); XCTAssertEqual(grey[1], 0)
    }
}
