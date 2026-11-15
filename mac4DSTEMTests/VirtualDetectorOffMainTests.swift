//
//  VirtualDetectorOffMainTests.swift
//  The virtual-image reduction runs off the main thread even when a MainActor caller awaits it (#427): CuboKit's reducers
//  are nonisolated(nonsending), so they inherit the caller's executor unless the app's entry point is `@concurrent`.
//

import XCTest
import Foundation
import DSTEMCore

@MainActor
final class VirtualDetectorOffMainTests: XCTestCase {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func demo() async throws -> (FourDArray, DatasetDescriptor) {
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        return (FourDArray(reader: source, descriptor: descriptor), descriptor)
    }

    /// The kit reports progress after each tile from the executor running the reduction. Mutation it catches: `@concurrent`
    /// removed from `kitImage` (the reduction, and so every progress call, runs on the main thread: red).
    func testAVirtualImageAwaitedFromTheMainActorIsReducedOffTheMainThread() async throws {
        let (data, descriptor) = try await demo()
        let onMain = Flag(), called = Flag()
        _ = try await VirtualDetector.tiledRun(
            data: data, descriptor: descriptor,
            aperture: Aperture(centerX: Float(descriptor.qx) / 2, centerY: Float(descriptor.qy) / 2, inner: 2, outer: 10),
            maximumTileRows: 1,
            progress: { _ in
                called.set()
                if Thread.isMainThread { onMain.set() }
            })
        XCTAssertTrue(called.isSet, "the premise: the kit reported progress")
        XCTAssertFalse(onMain.isSet, "the reduction ran on the main thread")
    }

    /// The same for the mean and maximum patterns (`tiledDPStatistics`).
    func testTheMeanAndMaximumPatternsAreReducedOffTheMainThread() async throws {
        let (data, descriptor) = try await demo()
        let onMain = Flag(), called = Flag()
        _ = try await VirtualDetector.tiledDPStatistics(
            data: data, descriptor: descriptor, maximumTileRows: 1,
            progress: { _ in
                called.set()
                if Thread.isMainThread { onMain.set() }
            })
        XCTAssertTrue(called.isSet, "the premise: the kit reported progress")
        XCTAssertFalse(onMain.isSet, "the reduction ran on the main thread")
    }
}
