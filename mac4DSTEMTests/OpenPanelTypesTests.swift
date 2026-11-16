//
//  OpenPanelTypesTests.swift
//  mac4DSTEM#458: File › Open greyed out .hspy, which the HDF5 reader opens (HyperSpy's files are HDF5). The pickers share one
//  list, and the built app's viewer type claims the same HDF5 extensions.
//

import XCTest
import UniformTypeIdentifiers
import DSTEMCore
@testable import mac4DSTEM

final class OpenPanelTypesTests: XCTestCase {
    /// Mutation: drop "hspy" from the list - red.
    func testTheOpenPanelOffersHyperSpyFiles() {
        XCTAssertTrue(FileRouting.openPanelExtensions.contains("hspy"))
        XCTAssertNotNil(UTType(filenameExtension: "hspy"), "a type the panel can filter on")
    }

    /// Mutation: drop "hspy" from the viewer document type in Info.plist - red.
    func testTheBuiltAppOpensHyperSpyFilesFromFinder() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let viewer = types.filter { $0["CFBundleTypeRole"] as? String == "Viewer" }
            .flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] }
        XCTAssertTrue(viewer.contains("hspy"), "\(viewer)")
    }
}
