//
//  ForeignVolumeWriteTests.swift
//  #526: the File menu's exports (data and bundle .h5, the session file, the preprocessed datacube) land on an exFAT drive.
//  Off a Mac volume the file is built in the temporary folder, then placed; on a Mac volume the direct path stays.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import FourDSTEMStudio

@MainActor
final class ForeignVolumeWriteTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("foreign-volume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        ForeignVolumeWrite.alwaysDetour = false
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    private func hdiutil(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private static let hdf5Magic: [UInt8] = [0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]
    private let map = ScalarResultMap(width: 2, height: 2, pixels: [0, 1, 2, 3], kind: "virtual_image",
                                      displayName: "Virtual image", valueUnits: "counts")

    /// The temporary folder is a Mac volume: the direct path. Mutation: the detour taken everywhere - red.
    func testAMacVolumeKeepsTheDirectPath() {
        XCTAssertFalse(ForeignVolumeWrite.needsDetour(scratch.appendingPathComponent("a.h5")))
    }

    /// The detour on any volume (the test switch): the bundle lands, replaces the file the Save panel confirmed, and leaves no
    /// part file; a write that fails leaves the old file as it was. Mutation: `finish` skipped, or the scratch left - red.
    func testTheDetourPlacesTheFileAndLeavesNothingElse() throws {
        ForeignVolumeWrite.alwaysDetour = true
        let destination = scratch.appendingPathComponent("bundle.h5")
        try Data("old".utf8).write(to: destination)
        try BraggVectorEMDWriter.writeScientificBundle(maps: [map], calibration: PixelCalibration(), to: destination)
        XCTAssertEqual(Array(try Data(contentsOf: destination).prefix(8)), Self.hdf5Magic)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), ["bundle.h5"])

        let before = try Data(contentsOf: destination)
        XCTAssertThrowsError(try ForeignVolumeWrite.write(to: destination) { target in
            try Data("partial".utf8).write(to: target)
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertEqual(try Data(contentsOf: destination), before, "a failed write leaves the destination as it was")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), ["bundle.h5"])
    }

    /// An exFAT disk image (hdiutil, unsigned test host): the volume asks for the detour, and a bundle export and a session
    /// file land on it. Mutation: needsDetour reading only exclusive renames' absence wrongly, or the writers not wrapped - red.
    func testExportsLandOnAnExFATVolume() throws {
        let image = scratch.appendingPathComponent("exfat.dmg")
        let mount = scratch.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let made = try hdiutil(["create", "-size", "32m", "-fs", "ExFAT", "-volname", "EMSFOREIGN", "-o", image.path])
        try XCTSkipIf(made.status != 0, "hdiutil create: \(made.output)")
        let attached = try hdiutil(["attach", image.path, "-nobrowse", "-noverify", "-mountpoint", mount.path])
        try XCTSkipIf(attached.status != 0, "hdiutil attach: \(attached.output)")
        defer { _ = try? hdiutil(["detach", mount.path, "-force"]) }

        let bundle = mount.appendingPathComponent("bundle.h5")
        XCTAssertTrue(ForeignVolumeWrite.needsDetour(bundle), "exFAT renames without RENAME_EXCL")
        try BraggVectorEMDWriter.writeScientificBundle(maps: [map], calibration: PixelCalibration(), to: bundle)
        XCTAssertEqual(Array(try Data(contentsOf: bundle).prefix(8)), Self.hdf5Magic)
        // Again onto the same name, as a confirmed replace in the Save panel.
        try BraggVectorEMDWriter.writeScientificBundle(maps: [map], calibration: PixelCalibration(), to: bundle)

        let vectors = BraggVectors(scanWidth: 1, scanHeight: 1, peaks: [[BraggPeak(x: 3, y: 4, intensity: 1)]])
        let session = mount.appendingPathComponent("scan.h5.mac4dstem.h5")
        try BraggVectorEMDWriter.write(vectors: vectors, qWidth: 8, qHeight: 8, calibration: PixelCalibration(), to: session)
        XCTAssertEqual(Array(try Data(contentsOf: session).prefix(8)), Self.hdf5Magic)
        let left = try FileManager.default.contentsOfDirectory(atPath: mount.path).filter { !$0.hasPrefix(".") || $0.hasPrefix(".macem-") }
        XCTAssertEqual(Set(left), ["bundle.h5", "scan.h5.mac4dstem.h5"], "no part file left on the drive")
    }
}
