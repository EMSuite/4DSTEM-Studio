//
//  MemoryGivenBackTests.swift
//  #261: a dataset's memory is given back when its window closes. Opens and closes the same real file ten times, through
//  `AppState` as a window does, and asserts that every `AppState` and `FourDArray` is freed and the malloc heap does not
//  grow. The heap is read with `malloc_zone_statistics`, not `phys_footprint`: macOS keeps freed large blocks dirty for
//  reuse, so the footprint stays near the largest transient after a close without anything being leaked (measured
//  2026-11-15, #261: a freed 500 MB array keeps a 501 MB footprint and a second one reuses it).
//
//  Needs the owner's data folder (`MACEM_DATA`, sim_Au_data_all_binned.h5); skipped without it, as the real-file tests are.
//

import Darwin
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class MemoryGivenBackTests: XCTestCase {

    private func heapInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    private func realFile() throws -> URL {
        let root = ProcessInfo.processInfo.environment["MACEM_DATA"]
        try XCTSkipIf(root == nil, "MACEM_DATA is not set (the owner's data folder)")
        let url = URL(fileURLWithPath: root!).appendingPathComponent("4dstem/training_dataset/sim_Au_data_all_binned.h5")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "sim_Au is machine-local and absent here")
        return url
    }

    /// One open-and-close: the configurator, Keep in memory on or off, one virtual image, then the window's close.
    /// Returns weak references to what the window owned.
    private func openAndClose(_ url: URL, keepInMemory: Bool, round: Int) async throws -> (AppState?, FourDArray?) {
        weak var released: AppState?
        weak var array: FourDArray?
        do {
            let state = AppState()
            released = state
            state.openFileForConfiguration(url: url)
            let deadline = Date().addingTimeInterval(120)
            while state.promotionRun.pendingLoad?.preview == nil, Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let pending = try XCTUnwrap(state.promotionRun.pendingLoad, "round \(round): no configurator")
            pending.keepInMemory = keepInMemory
            state.commitPendingLoad()
            while !(state.hasDataset && !state.datasetSession.isLoading), Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertTrue(state.hasDataset, "round \(round): the file did not open")
            array = state.datasetSession.fourD
            if keepInMemory {
                let resident = await state.datasetSession.fourD?.residentByteCount ?? 0
                XCTAssertGreaterThan(resident, 0, "round \(round): Keep in memory held nothing")
            }
            _ = await state.runVirtualDetector(quiet: true)
            state.windowClosed()
        }
        // The window's tasks finish on their own after the close; give them a moment.
        for _ in 0..<50 where released != nil || array != nil { try await Task.sleep(nanoseconds: 100_000_000) }
        return (released, array)
    }

    func testTenOpensAndClosesGiveTheirMemoryBack() async throws {
        let url = try realFile()
        for keepInMemory in [false, true] {
            var heap: [Int] = []
            for round in 0..<10 {
                let (state, array) = try await openAndClose(url, keepInMemory: keepInMemory, round: round)
                XCTAssertNil(state, "round \(round) (keep in memory \(keepInMemory)): the closed window's AppState is still alive")
                XCTAssertNil(array, "round \(round) (keep in memory \(keepInMemory)): the closed dataset's FourDArray is still alive")
                heap.append(heapInUse())
            }
            // Round 0 warms caches that live for the process (Metal pipelines, fonts); rounds 1-9 must not grow.
            let growth = heap[9] - heap[1]
            XCTAssertLessThan(growth, 16_000_000,
                              "keep in memory \(keepInMemory): the heap grew \(growth / 1_000_000) MB over nine opens and closes")
        }
    }
}
