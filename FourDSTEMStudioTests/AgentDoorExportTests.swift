//
//  AgentDoorExportTests.swift
//  #514: an export through the agent door answers with its outcome. A write that fails comes back as an error from the call (and in
//  get_window's operation.last_export), never as {"writing": …} followed by a line in the Output; and a data export lands on an
//  exFAT volume, where it failed with "Operation not supported".
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorExportTests: XCTestCase {
    private var door: AgentDoor!
    private var defaultsSuite = ""
    private var root: URL!
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-export-\(UUID().uuidString)")
            .appendingPathComponent("Agent")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaultsSuite = "agent-door-export-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.resultTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
        Mac4DSTEMAgentDoor.folder.use(folder: root)
        Mac4DSTEMAgentDoor.savesAllowed = true
    }

    override func tearDown() async throws {
        Mac4DSTEMAgentDoor.folder.use(folder: nil)
        Mac4DSTEMAgentDoor.savesAllowed = false
        door?.setEnabled(false)
        door = nil
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        if let root {
            chmod(root.path, 0o755)
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, text: String) {
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ])
        let (data, _) = try await session.data(for: request)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (result["isError"] as? Bool ?? true, text)
    }

    private func demoWithAResult() async throws -> AppState {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        await state.openDemoFixture()
        _ = await state.runVirtualDetector()
        XCTAssertNotNil(state.productDataExportMap(), "premise: a scalar result is shown")
        return state
    }

    private func lastExport(_ state: AppState) throws -> [String: Any] {
        let operation = try XCTUnwrap(state.agentSnapshot()["operation"] as? [String: Any])
        return try XCTUnwrap(operation["last_export"] as? [String: Any], "\(operation)")
    }

    /// A folder the app may not write into: the call is the error, and get_window keeps it. Mutation: export_result answers
    /// {"writing": …} and reports the failure only in the Output - red.
    func testARefusedWriteIsTheCallsError() async throws {
        let state = try await demoWithAResult()
        let written = try await call("export_result", ["what": "data", "name": "first"])
        XCTAssertFalse(written.refused, written.text)
        XCTAssertTrue(written.text.contains("\"saved\""), written.text)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("first.h5").path), "written before the answer")
        XCTAssertEqual(try lastExport(state)["state"] as? String, "written")

        XCTAssertEqual(chmod(root.path, 0o555), 0, "premise: a read-only Agent folder")
        let refused = try await call("export_result", ["what": "data", "name": "second"])
        XCTAssertTrue(refused.refused, "a write that fails is an error: \(refused.text)")
        XCTAssertTrue(refused.text.contains("second.h5 was not written"), refused.text)
        let last = try lastExport(state)
        XCTAssertEqual(last["state"] as? String, "failed")
        XCTAssertEqual(last["file"] as? String, "second.h5")
        XCTAssertNotNil(state.errorMessage, "the person sees it as the Export menu's own failures: an alert")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("second.h5").path), "no part file")
        withExtendedLifetime(state) {}
    }

    /// The copy into the Agent folder is a NEW file: a name that appeared meanwhile is never replaced, and a failed copy leaves nothing.
    func testTheCopyNeverReplacesAFile() throws {
        let source = root.appendingPathComponent("source.bin"), target = root.appendingPathComponent("target.bin")
        try Data([1, 2, 3]).write(to: source)
        try Data([9]).write(to: target)
        XCTAssertThrowsError(try Mac4DSTEMAgentDoor.copyAsNewFile(from: source, to: target)) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileWriteFileExists)
        }
        XCTAssertEqual(try Data(contentsOf: target), Data([9]))
        let missing = root.appendingPathComponent("missing.bin"), fresh = root.appendingPathComponent("fresh.bin")
        XCTAssertThrowsError(try Mac4DSTEMAgentDoor.copyAsNewFile(from: missing, to: fresh))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path), "a failed copy leaves no file")
    }

    // MARK: - exFAT

    private func hdiutil(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The Agent folder on an exFAT disk image (hdiutil, unsigned test host): export_result data writes its .h5 there. The two
    /// suspected causes are logged as EXFAT-DIAG lines (an HDF5 file built on the volume itself, and an exclusive rename there),
    /// so the CI log states which one the old path hit. Mutation: build and publish the file on the Agent folder's volume - red.
    func testADataExportLandsOnAnExFATVolume() async throws {
        let work = root.deletingLastPathComponent()
        let image = work.appendingPathComponent("exfat.dmg"), mount = work.appendingPathComponent("exfat", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let made = try hdiutil(["create", "-size", "32m", "-fs", "ExFAT", "-volname", "EMSEXFAT", "-o", image.path])
        XCTAssertEqual(made.status, 0, "hdiutil create: \(made.output)")
        let attached = try hdiutil(["attach", image.path, "-nobrowse", "-noverify", "-mountpoint", mount.path])
        XCTAssertEqual(attached.status, 0, "hdiutil attach: \(attached.output)")
        guard made.status == 0, attached.status == 0 else { return }
        defer { _ = try? hdiutil(["detach", mount.path, "-force"]) }
        let agent = mount.appendingPathComponent("Agent", isDirectory: true)
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)

        // What the old path did, for the log: the HDF5 writer on the volume, and the exclusive rename on it.
        let map = ScalarResultMap(width: 2, height: 2, pixels: [0, 1, 2, 3], kind: "diag", displayName: "diag", valueUnits: "counts")
        do {
            try BraggVectorEMDWriter.writeScientificBundle(maps: [map], calibration: PixelCalibration(), to: agent.appendingPathComponent("direct.h5"))
            print("EXFAT-DIAG HDF5 written on the exFAT volume itself: ok")
        } catch {
            print("EXFAT-DIAG HDF5 written on the exFAT volume itself: \(error)")
        }
        let a = agent.appendingPathComponent("a.bin"), b = agent.appendingPathComponent("b.bin")
        try Data([1]).write(to: a)
        let renamed = renamex_np(a.path, b.path, UInt32(RENAME_EXCL))
        print("EXFAT-DIAG renamex_np(RENAME_EXCL) on the exFAT volume: \(renamed == 0 ? "ok" : String(cString: strerror(errno)))")

        let state = try await demoWithAResult()
        Mac4DSTEMAgentDoor.folder.use(folder: agent)
        let written = try await call("export_result", ["what": "data", "name": "on_exfat"])
        XCTAssertFalse(written.refused, written.text)
        let file = agent.appendingPathComponent("on_exfat.h5")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the .h5 is on the exFAT volume")
        let bytes = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        XCTAssertGreaterThan(bytes, 0)
        XCTAssertEqual(try Data(contentsOf: file).prefix(8), Data([0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]), "an HDF5 file")
        Mac4DSTEMAgentDoor.folder.use(folder: root)
        withExtendedLifetime(state) {}
    }
}
