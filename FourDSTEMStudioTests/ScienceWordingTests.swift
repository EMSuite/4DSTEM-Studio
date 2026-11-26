//
//  ScienceWordingTests.swift
//  Two texts that stated the science wrongly (#488). The strain remedy said "the direct beam plus two more reflections"; the
//  fit needs `minNumPeaks` = 5 indexed disks (StrainMapping.compute, as py4DSTEM `fit_lattice_vectors`). The typed R–Q rotation
//  said py4DSTEM's `QR_rotation` is in degrees; it is radians, and degrees is `QR_rotation_degrees`.
//  Red before #488: both old sentences were in the sources.
//

import XCTest
@testable import FourDSTEMStudio

final class ScienceWordingTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Mutation: the note names another count than the fit's default, or the old sentence comes back - red.
    func testTheStrainRemedyNamesTheFitsMinimumPeakCount() throws {
        let settings = try source("FourDSTEMStudio/UI/MapSettings.swift")
        XCTAssertFalse(settings.contains("two more reflections"))
        XCTAssertTrue(settings.contains("needs at least 5 indexed disks at a position, as py4DSTEM's fit_lattice_vectors"))
        let mapping = try source("FourDSTEMStudio/Core/Analysis/StrainMapping.swift")
        XCTAssertTrue(mapping.contains("minNumPeaks: Int = 5,"), "the note's 5 is the fit's default")
    }

    /// Mutation: a text says QR_rotation is in degrees - red.
    func testTheRotationTextsNamePy4DSTEMsDegreesField() throws {
        for path in ["FourDSTEMStudio/UI/PrepareSettings.swift", "FourDSTEMStudio/App/AgentDoor/AgentDoorCalibration.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("(QR_rotation, degrees)"), path)
            XCTAssertFalse(text.contains("in degrees, py4DSTEM's QR_rotation \""), path)
            XCTAssertTrue(text.contains("QR_rotation_degrees"), path)
        }
    }
}
