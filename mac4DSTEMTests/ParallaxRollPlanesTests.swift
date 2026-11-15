import XCTest
import DSTEMCore

/// mac4DSTEM#305: the alignment's median re-centring rolled each whole stack into a new array (two more stacks at the peak,
/// none counted by the memory limit). The roll now runs in place through one plane of scratch; it must stay `np.roll` over
/// the two plane axes, plane by plane.
final class ParallaxRollPlanesTests: XCTestCase {
    func testTheInPlaceRollIsNumpyRollOverEachPlane() {
        // Two 3 x 4 planes, values 0..<24. np.roll(plane, (1, -1), axis=(0, 1)): out[r][c] = in[(r - 1) % 3][(c + 1) % 4].
        var stack = (0..<24).map(Float.init)
        ParallaxAligner.rollPlanes(&stack, planeCount: 12, count: 2, width: 4, height: 3, rowShift: 1, columnShift: -1)
        let first: [Float] = [9, 10, 11, 8, 1, 2, 3, 0, 5, 6, 7, 4]
        XCTAssertEqual(Array(stack[0..<12]), first)
        XCTAssertEqual(Array(stack[12..<24]), first.map { $0 + 12 }, "the second plane rolls on its own, not into the first")

        var unchanged = (0..<24).map(Float.init)
        ParallaxAligner.rollPlanes(&unchanged, planeCount: 12, count: 2, width: 4, height: 3, rowShift: 3, columnShift: -4)
        XCTAssertEqual(unchanged, (0..<24).map(Float.init), "a whole period is the identity")
    }
}
