import XCTest
@testable import mac4DSTEM

/// #448: the Bragg vector map's display does not depend on the intensity scale.
final class BraggMapDisplayScaleTests: XCTestCase {
    /// Mutation: back to `log10(1 + I)` - red (a disk shows at 0.02 % of the beam).
    func testDisksStayVisibleWhenIntensitiesAreFarBelowOne() {
        let shown = AppState.braggMapDisplayPixels([0, 1e-7, 1e-7, 2e-7, 5.7e-4])
        let beam = shown[4]
        XCTAssertEqual(shown[0], 0)
        XCTAssertGreaterThan(shown[1] / beam, 0.05, "a disk must show against the direct beam: \(shown)")
        XCTAssertLessThan(shown[1], shown[3])
        XCTAssertLessThan(shown[3], beam)
    }

    /// Mutation: the scale depends on the units - red.
    func testTheMapLooksTheSameInCountsAndInFractions() {
        let counts: [Float] = [0, 100, 100, 200, 570_000]
        let fractions = counts.map { $0 * 1e-9 }
        let a = AppState.braggMapDisplayPixels(counts)
        let b = AppState.braggMapDisplayPixels(fractions)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-4) }
    }

    func testAnEmptyMapStaysZero() {
        XCTAssertEqual(AppState.braggMapDisplayPixels([0, 0, -1]), [0, 0, 0])
    }
}
