//
//  AgentDoorHardeningTests.swift
//  The app's door tool layer after the code audit (issue #310): bounded text reads, exclusive creates for files a writer makes by
//  path, a moved Agent folder found again or said, quoted agent text, capped file names.
//

import XCTest
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorHardeningTests: XCTestCase {

    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("agent-hardening-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        Mac4DSTEMAgentDoor.folder.use(folder: nil)
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Mutation: the size check removed - red (the large file reads).
    func testATextFileAboveTheLimitIsRefusedUnread() throws {
        let big = scratch.appendingPathComponent("big.cif")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(Mac4DSTEMAgentDoor.agentTextByteLimit + 1))
        try handle.close()
        try Data("data_x\n".utf8).write(to: scratch.appendingPathComponent("small.cif"))
        Mac4DSTEMAgentDoor.folder.use(folder: scratch)

        guard case .failure(let refusal) = Mac4DSTEMAgentDoor.readAgentText("big.cif") else { return XCTFail("a huge file was read") }
        XCTAssertEqual(refusal.status, 413)
        guard case .success(let text) = Mac4DSTEMAgentDoor.readAgentText("small.cif") else { return XCTFail("a small file is read") }
        XCTAssertEqual(text, "data_x\n")
    }

    /// Mutation: the writer given the target itself, or a plain move that replaces - red (the link's target is written, or the
    /// file that appeared is replaced).
    func testANewFileNeverReplacesOrFollowsWhatAppearedAtItsName() throws {
        let fresh = scratch.appendingPathComponent("fresh.h5")
        try Mac4DSTEMAgentDoor.writeNewFile(at: fresh) { try Data("one".utf8).write(to: $0) }
        XCTAssertEqual(try Data(contentsOf: fresh), Data("one".utf8))

        // A file that appeared after the check: kept, and the write fails.
        XCTAssertThrowsError(try Mac4DSTEMAgentDoor.writeNewFile(at: fresh) { try Data("two".utf8).write(to: $0) })
        XCTAssertEqual(try Data(contentsOf: fresh), Data("one".utf8), "never replaced")

        // A link that appeared at the name, leading out: neither replaced nor followed.
        let outside = scratch.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outside)
        let link = scratch.appendingPathComponent("link.h5")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try Mac4DSTEMAgentDoor.writeNewFile(at: link) { try Data("evil".utf8).write(to: $0) })
        XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8), "the link was not followed")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), outside.path, "the link was not replaced")

        // The scratch file of a failed write is gone.
        let left = try FileManager.default.contentsOfDirectory(atPath: scratch.path).sorted()
        XCTAssertEqual(left, ["fresh.h5", "link.h5", "outside.txt"])
    }

    /// Mutation: the failure swallowed by try? - red (the generic "no folder chosen" answer).
    func testAFolderThatCanNoLongerBeFoundIsSaid() throws {
        let folder = scratch.appendingPathComponent("Agent")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.removeItem(at: folder)
        let agentFolder = AgentFolder()
        agentFolder.use(bookmark: bookmark)
        XCTAssertNil(agentFolder.url)
        XCTAssertNotEqual(agentFolder.missingMessage, AgentFolder.noFolder, "a chosen folder that is gone is not 'none chosen'")
        XCTAssertTrue(agentFolder.missingMessage.contains("choose it again"), agentFolder.missingMessage)
        agentFolder.use(bookmark: nil)
        XCTAssertEqual(agentFolder.missingMessage, AgentFolder.noFolder)
    }

    /// Mutation: values written verbatim - red.
    func testAgentTextIsQuotedInTheLog() {
        XCTAssertEqual(Mac4DSTEMAgentDoor.quotedAgentText("0.3"), "0.3", "numbers stay as they are")
        XCTAssertEqual(Mac4DSTEMAgentDoor.quotedAgentText("typedZones"), "typedZones")
        XCTAssertEqual(Mac4DSTEMAgentDoor.quotedAgentText("a.cif\nCalibration cleared."), "\u{201C}a.cif Calibration cleared.\u{201D}")
        XCTAssertEqual(Mac4DSTEMAgentDoor.quotedAgentText("say \"hi\""), "\u{201C}say 'hi'\u{201D}")
        let long = Mac4DSTEMAgentDoor.quotedAgentText(String(repeating: "x", count: 500) + " ")
        XCTAssertLessThan(long.count, Mac4DSTEMAgentDoor.agentTextDisplayLimit + 4)
        let line = Mac4DSTEMAgentDoor.agentChangeLine("the phase", ["path": "sub/θ′.cif\r\nok", "index": "1"])
        XCTAssertEqual(line, "An agent set the phase: index 1, path \u{201C}sub/θ′.cif  ok\u{201D}.")
    }

    /// Mutation: no cap - red.
    func testAGivenFileNameHasALengthCap() {
        let long = String(repeating: "a", count: Mac4DSTEMAgentDoor.fileNameByteLimit + 1)
        guard case .failure = Mac4DSTEMAgentDoor.fileName(long, default: "x") else { return XCTFail("a 201-byte name was taken") }
        guard case .success(let shortened) = Mac4DSTEMAgentDoor.fileName(nil, default: long) else { return XCTFail("the default fits") }
        XCTAssertEqual(shortened.utf8.count, Mac4DSTEMAgentDoor.fileNameByteLimit + 4, "the dataset's own name is shortened, .png added")
    }
}
