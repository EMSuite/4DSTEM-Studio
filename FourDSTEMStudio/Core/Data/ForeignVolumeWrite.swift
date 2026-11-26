//
//  ForeignVolumeWrite.swift
//  Role: an export onto a volume that is not a Mac's own kind (exFAT, FAT, many network shares) is built in this Mac's
//        temporary folder and then placed (issue #526). The kit writers build their file under a scratch name on the
//        destination's own volume and publish it there by rename, with HDF5 opening it; an exFAT drive refused that with
//        "Operation not supported" (#514, the agent door's export). Here the file is built where both work (APFS), its bytes
//        are copied onto the destination's volume as a new file, and that copy is renamed onto the destination, which a plain
//        rename does on every volume macOS writes. A Mac volume (APFS, HFS+) keeps the direct path: no second copy of a large
//        datacube.
//
//        The rename replaces the destination, as the direct path does: the person confirmed the replace in the Save panel, and a
//        session file is rewritten in place. A failed or cancelled write leaves the destination as it was and no part file.
//

import Darwin
import Foundation

package nonisolated enum ForeignVolumeWrite {
    /// Tests: take the detour on any volume.
    nonisolated(unsafe) package static var alwaysDetour = false

    /// Whether a file at `destination` is built off its volume: the volume cannot rename exclusively or lock files (the two
    /// things the kit's publish and HDF5 ask of it). Unknown (the folder cannot be read) keeps the direct path, as before.
    package static func needsDetour(_ destination: URL) -> Bool {
        if alwaysDetour { return true }
        let folder = destination.deletingLastPathComponent()
        guard let values = try? folder.resourceValues(forKeys: [.volumeSupportsExclusiveRenamingKey,
                                                                .volumeSupportsAdvisoryFileLockingKey]) else { return false }
        return values.volumeSupportsExclusiveRenaming == false || values.volumeSupportsAdvisoryFileLocking == false
    }

    /// Where a writer builds the file for `destination`, and how it reaches it.
    package struct Plan {
        /// The path to hand the writer: `destination` itself, or a file in the temporary folder.
        package let target: URL
        let destination: URL
        let folder: URL?

        /// The writer finished: a detoured file is placed onto the destination. Nothing to do on the direct path.
        package func finish() throws {
            guard let folder else { return }
            defer { try? FileManager.default.removeItem(at: folder) }   // try? OK: a leftover scratch folder holds no result
            try ForeignVolumeWrite.place(target, onto: destination)
        }

        /// The writer failed or was cancelled: the scratch goes, the destination is untouched.
        package func discard() {
            if let folder { try? FileManager.default.removeItem(at: folder) }   // try? OK: as above
        }
    }

    package static func plan(for destination: URL) throws -> Plan {
        guard needsDetour(destination) else { return Plan(target: destination, destination: destination, folder: nil) }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return Plan(target: folder.appendingPathComponent(destination.lastPathComponent), destination: destination, folder: folder)
    }

    /// `body` writes the file at the URL it is given; the file then lands on `destination`.
    package static func write(to destination: URL, _ body: (URL) throws -> Void) throws {
        let plan = try plan(for: destination)
        do {
            try body(plan.target)
            try plan.finish()
        } catch {
            plan.discard()
            throw error
        }
    }

    /// `file`'s bytes into a new file on `destination`'s volume (O_EXCL, no link followed), flushed, then renamed onto it.
    package static func place(_ file: URL, onto destination: URL) throws {
        // The system's item-replacement folder on the destination's volume: the sandbox lets the app write there for a file the
        // person chose (it does not for any other name beside it), and the rename stays on one volume. Beside the destination
        // where the system has none (tests, tools).
        let replacement = try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                       appropriateFor: destination, create: true)
        defer { if let replacement { try? FileManager.default.removeItem(at: replacement) } }   // try? OK: an empty folder
        let sibling = (replacement ?? destination.deletingLastPathComponent())
            .appendingPathComponent(".macem-\(UUID().uuidString).tmp", isDirectory: false)
        let input = open(file.path, O_RDONLY)
        guard input >= 0 else { throw failure("reading the finished file", errno) }
        defer { close(input) }
        let output = open(sibling.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard output >= 0 else { throw failure("creating the file beside \(destination.lastPathComponent)", errno) }
        var placed = false, closed = false
        defer {
            if !closed { close(output) }
            if !placed { unlink(sibling.path) }
        }
        do {
            let size = 8 << 20
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
            defer { buffer.deallocate() }
            while true {
                let read = Darwin.read(input, buffer, size)
                if read < 0 { throw failure("reading the finished file", errno) }
                if read == 0 { break }
                var offset = 0
                while offset < read {
                    let wrote = Darwin.write(output, buffer + offset, read - offset)
                    if wrote < 0 { throw failure("writing \(destination.lastPathComponent)", errno) }
                    offset += wrote
                }
            }
            if fsync(output) != 0 { throw failure("flushing \(destination.lastPathComponent)", errno) }
            closed = true
            if close(output) != 0 { throw failure("closing \(destination.lastPathComponent)", errno) }
        }
        guard Darwin.rename(sibling.path, destination.path) == 0 else {
            throw failure("placing \(destination.lastPathComponent)", errno)
        }
        placed = true
    }

    private static func failure(_ operation: String, _ code: Int32) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"])
    }
}
