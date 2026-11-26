//
//  AgentDoorValuesTests.swift
//  #515: the agent door hands over numbers as numbers: the displayed result's fields as Float32 (.npy or base64), the Bragg
//  vectors of every position in one file, and get_detected_disks over a rectangle of positions.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
@testable import FourDSTEMStudio

@MainActor
final class AgentDoorValuesTests: XCTestCase {
    private var door: AgentDoor!
    private var defaultsSuite = ""
    private var root: URL!
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-values-\(UUID().uuidString)")
            .appendingPathComponent("Agent")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaultsSuite = "agent-door-values-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.valueTools)
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
        if let root { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
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

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    /// numpy's .npy 1.0: magic, version, a header padded to 64 bytes ending in a newline, then little-endian float32 in C order.
    /// Mutation: the header not padded, or the shape written (width, height) - red.
    func testTheNpyFileIsNumpysFormat() throws {
        let data = Mac4DSTEMAgentDoor.npyData([1, 2, 3, .nan, -0.5, 6], height: 2, width: 3)
        XCTAssertEqual(Array(data.prefix(8)), [0x93] + Array("NUMPY".utf8) + [1, 0])
        let length = Int(data[8]) | Int(data[9]) << 8
        XCTAssertEqual((10 + length) % 64, 0)
        let header = try XCTUnwrap(String(data: data.subdata(in: 10..<(10 + length)), encoding: .ascii))
        XCTAssertTrue(header.hasPrefix("{'descr': '<f4', 'fortran_order': False, 'shape': (2, 3), }"), header)
        XCTAssertTrue(header.hasSuffix("\n"))
        let body = data.subdata(in: (10 + length)..<data.count)
        XCTAssertEqual(body.count, 6 * 4)
        let values = stride(from: 0, to: body.count, by: 4).map { offset -> Float in
            Float(bitPattern: body.subdata(in: offset..<(offset + 4)).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        }
        XCTAssertEqual(values[4], -0.5)
        XCTAssertTrue(values[3].isNaN)
        XCTAssertEqual(values[5], 6)
    }

    /// The displayed virtual image's values come back exactly, inline and as a file. Mutation: the values clipped to the display
    /// range, or the file written as PNG bytes - red.
    func testTheResultsValuesComeBackAsTheyAre() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        await state.openDemoFixture()
        _ = await state.runVirtualDetector()
        let map = try XCTUnwrap(state.productDataExportMap(), "premise: a scalar result is shown")

        let listed = try object(try await call("get_result_values").text)
        let names = try XCTUnwrap(listed["fields"] as? [[String: Any]]).compactMap { $0["name"] as? String }
        XCTAssertEqual(names.first, map.kind)

        let inline = try await call("get_result_values", ["field": map.kind, "format": "base64"])
        XCTAssertFalse(inline.refused, inline.text)
        let answer = try object(inline.text)
        XCTAssertEqual(answer["shape"] as? [Int], [map.height, map.width])
        let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(answer["data_base64"] as? String)))
        XCTAssertEqual(bytes, Mac4DSTEMAgentDoor.littleEndianBytes(map.pixels))

        let saved = try await call("get_result_values", ["field": map.kind, "name": "values/virtual"])
        XCTAssertFalse(saved.refused, saved.text)
        XCTAssertEqual(try object(saved.text)["saved"] as? String, "values/virtual.npy")
        let file = try Data(contentsOf: root.appendingPathComponent("values/virtual.npy"))
        XCTAssertEqual(file, Mac4DSTEMAgentDoor.npyData(map.pixels, height: map.height, width: map.width))
        let again = try await call("get_result_values", ["field": map.kind, "name": "values/virtual"])
        XCTAssertTrue(again.refused, "a file is never replaced")

        let unknown = try await call("get_result_values", ["field": "nope"])
        XCTAssertTrue(unknown.refused)
    }

    /// Every position's disks in one file, and a rectangle of positions in one call. Mutation: the CSV's scan_x and scan_y
    /// swapped, or the rectangle read row by row with the wrong stride - red.
    func testEveryPositionsDisksInOneFileAndARectangleInOneCall() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        await state.openDemoFixture(calibrated: false)

        let none = try await call("export_bragg_vectors")
        XCTAssertTrue(none.refused)
        XCTAssertTrue(none.text.contains("run_task"), none.text)

        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        let vectors = try XCTUnwrap(state.resultPresentation.braggVectors, state.statusText)

        let h5 = try await call("export_bragg_vectors", ["name": "disks"])
        XCTAssertFalse(h5.refused, h5.text)
        let h5Answer = try object(h5.text)
        XCTAssertEqual(h5Answer["disks"] as? Int, vectors.totalPeakCount)
        let header = try Data(contentsOf: root.appendingPathComponent("disks.h5")).prefix(8)
        XCTAssertEqual(Array(header), [0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A], "an HDF5 file")

        let csv = try await call("export_bragg_vectors", ["format": "csv", "name": "disks"])
        XCTAssertFalse(csv.refused, csv.text)
        let lines = try String(contentsOf: root.appendingPathComponent("disks.csv"), encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.first, "scan_x,scan_y,x_px,y_px,intensity")
        XCTAssertEqual(lines.count - 1, vectors.totalPeakCount)

        let x = min(1, vectors.scanWidth - 1), y = min(2, vectors.scanHeight - 1)
        let rectangle = try await call("get_detected_disks", ["x0": 0, "y0": 0, "x1": x, "y1": y])
        XCTAssertFalse(rectangle.refused, rectangle.text)
        let positions = try XCTUnwrap(try object(rectangle.text)["positions"] as? [[String: Any]])
        XCTAssertEqual(positions.count, (x + 1) * (y + 1))
        let last = try XCTUnwrap(positions.last)
        XCTAssertEqual(last["x"] as? Int, x)
        XCTAssertEqual(last["y"] as? Int, y)
        XCTAssertEqual((last["disks"] as? [Any])?.count, vectors.peaks[y * vectors.scanWidth + x].count)

        let half = try await call("get_detected_disks", ["x0": 0, "y0": 0])
        XCTAssertTrue(half.refused, "a rectangle needs its four corners")
        let outside = try await call("get_detected_disks", ["x0": 0, "y0": 0, "x1": vectors.scanWidth, "y1": 0])
        XCTAssertTrue(outside.refused)
    }

    /// Mutation: the CSV row's scan position from the wrong axis - red.
    func testTheCSVNamesEachDisksScanPosition() {
        let vectors = BraggVectors(scanWidth: 2, scanHeight: 2, peaks: [
            [], [BraggPeak(x: 10.5, y: 20, intensity: 3)], [BraggPeak(x: 1, y: 2, intensity: 0.25)], [],
        ])
        let text = String(decoding: Mac4DSTEMAgentDoor.braggCSV(vectors), as: UTF8.self)
        XCTAssertEqual(text, "scan_x,scan_y,x_px,y_px,intensity\n1,0,10.5,20,3\n0,1,1,2,0.25\n")
    }
}
