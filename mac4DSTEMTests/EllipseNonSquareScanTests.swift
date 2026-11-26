import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Refuter D, item 3: the row/column convention at AppState.calibrateEllipse on NON-square patterns, through the app's own
/// entry point (not the harness). Values printed as bit patterns are compared with the pre-switch code (7f192da9's
/// EllipseCalibration.swift compiled standalone on the same pixels).
@MainActor
final class EllipseNonSquareScanTests: XCTestCase {
    private struct RD_SM64 { var s: UInt64; mutating func next() -> Double { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; z ^= z >> 31; return Double(z >> 11) / Double(1 << 53) } }
    private func rdRingPixels(width: Int, height: Int, cRow: Double, cCol: Double, a: Double, b: Double, theta: Double, sigma: Double, seed: UInt64) -> [Float] {
        var rng = RD_SM64(s: seed)
        var px = [Float](repeating: 0, count: width * height)
        let ct = cos(theta), st = sin(theta)
        for r in 0..<height { for c in 0..<width {
            let dr = Double(r) - cRow, dc = Double(c) - cCol
            // coordinates along the semi-major axis (tilted theta from the ROW axis) and the semi-minor
            let u = dr * ct + dc * st, v = -dr * st + dc * ct
            let rho = (u * u / (a * a) + v * v / (b * b)).squareRoot()
            let radial = (rho - 1) * (a + b) / 2
            let value = 100 * exp(-radial * radial / (2 * sigma * sigma)) + 2 * rng.next()
            px[r * width + c] = Float(value)
        } }
        return px
    }
    private let rdCases: [(Int, Int, Double, Double, Double, Double, Double)] = [
        (80, 64, 34, 30, 22, 18, 0.4), (50, 90, 40, 22, 19, 17, 1.0), (64, 80, 30, 34, 22, 18, 0.4), (96, 48, 20, 55, 21, 19.5, 2.3)]

    func testCalibrateEllipseOnNonSquarePatternsRecoversRowColumnTruthAndMatchesPreSwitchBits() async throws {
        var fits: [[Double]] = []   // per case: centerQX, centerQY, a, b, theta, normalizedResidual
        for (i, k) in rdCases.enumerated() {
            let (w, h, cr, cc, a, b, th) = k
            let app = AppState()
            await app.openDemoFixture(calibrated: true)
            app.meanPattern = DiffractionPattern(qy: h, qx: w, pixels: rdRingPixels(width: w, height: h, cRow: cr, cCol: cc, a: a, b: b, theta: th, sigma: 2, seed: UInt64(100 + i)))
            app.navigation.analysisMode = .virtualDetector
            // the aperture centre is (x = column, y = row); the app hands the fit (row, column)
            app.aperture = Aperture(centerX: Float(cc - 0.9), centerY: Float(cr + 0.7), inner: 0, outer: 10)
            app.calibrationSession.ellipseFitInnerRadius = 10
            app.calibrationSession.ellipseFitOuterRadius = 30
            await app.calibrateEllipse()
            let fit = try XCTUnwrap(app.calibrationSession.lastEllipseFit, "case \(i) did not fit: \(app.statusText)")
            fits.append([fit.centerQX, fit.centerQY, fit.a, fit.b, fit.theta, fit.normalizedResidual])
            XCTAssertEqual(fit.centerQX, cr, accuracy: 0.05, "case \(i): the fit's centerQX is the ROW")
            XCTAssertEqual(fit.centerQY, cc, accuracy: 0.05, "case \(i): the fit's centerQY is the COLUMN")
            XCTAssertEqual(fit.a, a, accuracy: 0.05); XCTAssertEqual(fit.b, b, accuracy: 0.05)
            XCTAssertEqual(fit.theta, th, accuracy: 0.01)
            XCTAssertEqual(app.calibrationSession.calibration.ellipseTheta, fit.theta)
        }
        // Bit patterns of cqx cqy a b theta res. First recorded from the pre-switch code (7f192da9's EllipseCalibration.swift,
        // standalone -O, same pixels); re-recorded 26 Nov 2026 after DiffractoKit 0.24's ring fit left the central Gaussian
        // free in sign as py4DSTEM does (DiffractoKit#243): case 2 moved by up to 8e-6 relative, the others by a few ulp.
        let expected: [[UInt64]] = [
            [4629981658662369881, 4629137681650380854, 4626885692158328426, 4625760090874246504, 4600883453294973432, 4573222263564240291],
            [4630826244857649606, 4626885599076081178, 4626041530532315323, 4625478833459681286, 4607179251661257652, 4573035947952047526],
            [4629137384514753817, 4629981786308793612, 4626885689421957633, 4625759219501800009, 4600872131021610889, 4573216621661533156],
            [4626322768737394470, 4632937431348229012, 4626604513563305070, 4626182430775386321, 4612360510235552402, 4573158931434066736],
        ]
        // Compared as numbers, not parsed back from printed text (the first version split a printed line and dropped its first
        // integer, which only worked while the model name held no integer).
        XCTAssertEqual(fits.count, expected.count)
        // The bit patterns of this run, in `expected`'s layout: what to record when a reviewed change moves the fit.
        let bits = fits.map { $0.map(\.bitPattern) }
        for (i, (fit, old)) in zip(fits, expected).enumerated() {
            XCTAssertEqual(fit.count, 6)
            for (new, oldBits) in zip(fit, old) {
                let b = Double(bitPattern: oldBits)
                // Measured: up to 911 ulp (a, case 1: 1.7e-13 relative) between the Xcode test host and the standalone build, and
                // 1.9e-11 relative (centerQX, case 2) after DiffractoKit 0.24's fit. The rule (D12) is the float64 assert_allclose
                // default, rtol 1e-7; the row/column truth above is what this test guards.
                XCTAssertEqual(new, b, accuracy: 1e-7 * abs(b), "case \(i); this run's bits: \(bits)")
            }
        }
    }
}
