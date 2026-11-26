//
//  AgentFolderPanelTests.swift
//  mac4DSTEM#457: Settings > Agents > Folder > Choose… opened nothing (`.fileImporter` on a Settings Form section never
//  presents). The button now opens an AppKit panel for one folder. Whether it presents is a screen check in the release walk.
//

import XCTest
@testable import FourDSTEMStudio

@MainActor
final class AgentFolderPanelTests: XCTestCase {
    /// Mutation: the panel lets a file or several folders be chosen - red.
    func testThePanelChoosesOneFolder() {
        let panel = AgentFolderPanel.make()
        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
    }

    /// Mutation: the Settings section goes back to `.fileImporter` - red.
    func testSettingsNoLongerUsesAFileImporterForTheAgentFolder() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("FourDSTEMStudio/UI/SettingsWindow.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("AgentFolderPanel.choose()"))
        XCTAssertFalse(source.contains("allowedContentTypes: [.folder]"))
    }
}
