//
//  PrecipitateTests.swift
//  The precipitate objects on ImagoKit 0.7.0 (suite task 39): the app's class-map step takes its labelling, every measurement and
//  the edge-corrected density from the kit, so these tests hold what the APP adds around them: that the objects are the kit's
//  (same labels, Feret as the needle length), the density is the kit's closed form on the analysed area, and the no-calibration
//  refusal. The density's own arithmetic is pinned in ImagoKit (`ArealDensityTests`); the reflection finder that lived here was
//  unwired and is gone (the kit's `PeakLocalMax` serves a future one).
//

import XCTest
import DSTEMCore
import ImagoCore

final class PrecipitateTests: XCTestCase {

    private func classObjects(_ labels: [Int32], width: Int, height: Int, notIndexed: Set<Int32> = [9],
                              pixelSize: Double?, unit: String? = "nm") throws -> PrecipitateSegmentation.ClassMapObjects {
        try PrecipitateSegmentation.classObjects(
            labels: labels, width: width, height: height,
            roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: notIndexed),
            pixelSize: pixelSize, pixelUnit: unit)
    }

    /// 10 x 10 scan, 80 analysed positions (20 are not indexed), class 1: one pixel at (row 5, col 5) and a 4 x 2 block at rows 2-3,
    /// cols 3-6. The density is the kit's: each counted object weighted W·H / ((W − bx − 1)(H − by − 1)): (100/64 + 100/35) / 80.
    /// Mutation: the weights dropped (count / area), or the analysed pixels replaced by the frame - red.
    func testTheDensityIsTheKitsEdgeCorrectedClosedFormOnTheAnalysedArea() throws {
        var labels = [Int32](repeating: 0, count: 100)
        labels[55] = 1
        for r in 2...3 { for c in 3...6 { labels[r * 10 + c] = 1 } }
        for i in 80..<100 { labels[i] = 9 }
        let result = try classObjects(labels, width: 10, height: 10, pixelSize: 1)
        let cls = try XCTUnwrap(result.classes.first)
        XCTAssertEqual(result.analysedPixels, 80)
        XCTAssertEqual(cls.density.counted, 2)
        XCTAssertEqual(try XCTUnwrap(cls.density.arealDensity), (100.0 / 64 + 100.0 / 35) / 80, accuracy: 1e-12)
        XCTAssertEqual(cls.density.validation, "none")
    }

    /// No calibration, no density: the counts and the lengths stay.
    func testNoPixelSizeNoDensity() throws {
        var labels = [Int32](repeating: 0, count: 100)
        labels[55] = 1
        let cls = try XCTUnwrap(try classObjects(labels, width: 10, height: 10, pixelSize: nil, unit: nil).classes.first)
        XCTAssertNil(cls.density.arealDensity)
        XCTAssertEqual(cls.density.counted, 1)
    }

    /// An object touching the scan edge is not counted and adds no weight.
    func testEdgeObjectsAreListedAndNotCounted() throws {
        var labels = [Int32](repeating: 0, count: 100)
        labels[55] = 1
        labels[0] = 1; labels[1] = 1
        let cls = try XCTUnwrap(try classObjects(labels, width: 10, height: 10, pixelSize: 1).classes.first)
        XCTAssertEqual(cls.objects.count, 2)
        XCTAssertEqual(cls.density.counted, 1)
        XCTAssertEqual(cls.density.edgeExcluded, 1)
        XCTAssertEqual(try XCTUnwrap(cls.density.arealDensity), (100.0 / 64) / 100, accuracy: 1e-12)
    }

    /// The needle length is the Feret diameter, the kit's, and the table's other columns are the kit's too: a diagonal needle's
    /// objects equal `Segmentation.regionProperties` on the same labels. Mutation: lengthPx back to the principal-axis extent - red.
    func testTheNeedleLengthIsTheFeretDiameterAndTheColumnsAreTheKits() throws {
        let width = 24, height = 24
        var labels = [Int32](repeating: 0, count: width * height)
        for k in 0..<14 { labels[(5 + k) * width + (4 + k)] = 1; labels[(5 + k) * width + (5 + k)] = 1 }   // a 2-px-wide diagonal
        let cls = try XCTUnwrap(try classObjects(labels, width: width, height: height, pixelSize: nil, unit: nil).classes.first)
        let object = try XCTUnwrap(cls.objects.first)
        let mask = labels.map { $0 == 1 }
        let image = try Segmentation.label(mask, width: width, height: height, connectivity: .eight)
        let kit = try XCTUnwrap(try Segmentation.regionProperties(image).first)
        XCTAssertEqual(Double(object.lengthPx), kit.feretDiameterMax, accuracy: 1e-5 * kit.feretDiameterMax)
        XCTAssertEqual(object.perimeterPx, kit.perimeter)
        XCTAssertEqual(object.equivalentDiameterPx, kit.equivalentDiameterArea)
        XCTAssertEqual(object.solidity, kit.solidity)
        XCTAssertEqual(object.axisMajorLengthPx, kit.moments.axisMajorLength)
        // The Feret length of a diagonal is longer than the old principal-axis extent + 1 by a fraction of a pixel, never by a pixel.
        XCTAssertGreaterThan(Double(object.lengthPx), Double(kit.moments.lengthPx) - 1)
        XCTAssertLessThan(abs(Double(object.lengthPx) - kit.moments.lengthPx), 1.5)
    }

    /// Ids run across classes in the order the classes are visited, each class largest first.
    func testIdsRunAcrossClassesLargestFirst() throws {
        var labels = [Int32](repeating: 0, count: 100)
        labels[11] = 1; labels[33] = 1; labels[34] = 1                  // class 1: a pixel, then a 2-pixel bar
        labels[66] = 2                                                   // class 2
        let result = try PrecipitateSegmentation.classObjects(
            labels: labels, width: 10, height: 10, roles: .init(precipitateClasses: [1, 2], matrix: [0], notIndexed: [9]),
            pixelSize: nil, pixelUnit: nil)
        XCTAssertEqual(result.classes.map { $0.objects.map(\.id) }, [[1, 2], [3]])
        XCTAssertEqual(result.classes[0].objects.map(\.area), [2, 1])
    }
}

/// mac4DSTEM#300: a class map whose data does not hold together is refused with a sentence, not a `precondition` trap.
final class PrecipitateClassMapRefusalTests: XCTestCase {
    private func refusal(_ labels: [Int32], width: Int, height: Int,
                         roles: PrecipitateSegmentation.LabelRoles) -> PrecipitateSegmentation.Refusal? {
        do {
            _ = try PrecipitateSegmentation.classObjects(labels: labels, width: width, height: height, roles: roles,
                                                         pixelSize: nil, pixelUnit: nil)
            return nil
        } catch let refusal as PrecipitateSegmentation.Refusal {
            return refusal
        } catch {
            XCTFail("refused as \(error)")
            return nil
        }
    }

    /// Mutation: any guard back to a `precondition` - the test process crashes, red.
    func testAMalformedClassMapIsRefused() {
        let roles = PrecipitateSegmentation.LabelRoles(precipitateClasses: [1], matrix: [0], notIndexed: [9])
        XCTAssertNotNil(refusal([0, 1, 1], width: 2, height: 2, roles: roles), "labels that do not fill the map")
        XCTAssertNotNil(refusal([], width: -1, height: 0, roles: roles), "negative dimensions")
        XCTAssertNotNil(refusal([], width: Int.max, height: 2, roles: roles), "dimensions whose product overflows")
        XCTAssertNotNil(refusal([0, 1, 1, 0], width: 2, height: 2,
                                roles: .init(precipitateClasses: [1], matrix: [1], notIndexed: [9])), "a label in two roles")
        XCTAssertNil(refusal([0, 1, 1, 0], width: 2, height: 2, roles: roles), "a well-formed map")
        let message = refusal([0], width: 2, height: 2, roles: roles)?.localizedDescription ?? ""
        XCTAssertTrue(message.hasPrefix("The precipitate objects cannot be found:"), message)
    }
}
