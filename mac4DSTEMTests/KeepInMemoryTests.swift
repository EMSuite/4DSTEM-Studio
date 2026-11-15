import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane K2 (owner 2026-10-01): the per-open "Keep in memory" switch.
@MainActor
final class KeepInMemoryTests: XCTestCase {

    private let GB: UInt64 = 1 << 30

    private func decide(_ cube: UInt64, limit: UInt64 = 40, ram: UInt64 = 64,
                        buffer: UInt64 = 1000) -> KeepInMemoryDecision {
        KeepInMemoryDecision.decide(
            cubeBytes: Int(cube * GB), limitBytes: limit * GB,
            maxBufferBytes: buffer * GB, physicalMemory: ram * GB)
    }

    /// Mutation: refuse threshold compared with `>=` or against RAM instead of the limit.
    func testRefusedOnlyAboveTheGPUWorkingSetLimit() {
        XCTAssertEqual(decide(41), .refused)
        XCTAssertNotEqual(decide(40), .refused, "at the limit is still allowed")
        XCTAssertNotEqual(decide(39), .refused)
    }

    /// Mutation: warn fraction 0.5 changed, or warn applied to refused/fits.
    func testWarnsAboveHalfOfPhysicalMemoryOnly() {
        XCTAssertEqual(decide(33), .warn)
        XCTAssertEqual(decide(32), .fits, "exactly half does not warn")
        XCTAssertEqual(decide(10), .fits)
    }

    /// Mutation: dropping the maxBufferLength term (UI and shouldAdmit could disagree).
    func testOneMetalBufferIsAHardCeilingToo() {
        XCTAssertEqual(decide(20, buffer: 16), .refused)
    }

    /// #314: the switch starts at the default rule and follows it until the person sets it.
    func testTheSwitchStartsAtTheRuleAndTheChoiceWins() async throws {
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        let pending = PendingLoad(
            source: descriptor, reader: reader,
            url: URL(fileURLWithPath: descriptor.filePath),
            accessedSecurityScope: false, fileByteCount: nil)
        // The demo cube is tiny: it fits a quarter of any Mac, so it is kept by default.
        XCTAssertNil(pending.keepInMemoryChoice)
        XCTAssertTrue(pending.keepsInMemoryByDefault)
        XCTAssertTrue(pending.keepInMemory)
        XCTAssertTrue(pending.effectiveKeepInMemory)
        pending.keepInMemory = false
        XCTAssertEqual(pending.keepInMemoryChoice, false)
        XCTAssertFalse(pending.effectiveKeepInMemory, "the person's off wins over the rule")
        // What other windows hold counts against the share.
        let fresh = PendingLoad(source: descriptor, reader: reader, url: URL(fileURLWithPath: descriptor.filePath),
                                accessedSecurityScope: false, fileByteCount: nil)
        fresh.heldElsewhere = Int(ProcessInfo.processInfo.physicalMemory)
        XCTAssertFalse(fresh.keepInMemory, "a Mac whose memory other windows already hold streams by default")
    }

    /// #314. Mutation: share changed from a quarter, `<=` made `<`, or what other windows hold left out.
    func testTheDefaultKeepsACubeUnderAQuarterOfTheRAMCountingOtherWindows() {
        let ram = 64 * GB
        XCTAssertEqual(KeepInMemoryDecision.defaultShareOfRAM, 0.25)
        XCTAssertTrue(KeepInMemoryDecision.keepsByDefault(cubeBytes: Int(16 * GB), heldElsewhere: 0, physicalMemory: ram),
                      "exactly a quarter is kept")
        XCTAssertFalse(KeepInMemoryDecision.keepsByDefault(cubeBytes: Int(16 * GB) + 1, heldElsewhere: 0, physicalMemory: ram))
        XCTAssertTrue(KeepInMemoryDecision.keepsByDefault(cubeBytes: Int(10 * GB), heldElsewhere: Int(6 * GB), physicalMemory: ram))
        XCTAssertFalse(KeepInMemoryDecision.keepsByDefault(cubeBytes: Int(10 * GB), heldElsewhere: Int(7 * GB), physicalMemory: ram),
                       "what other windows hold counts")
        XCTAssertFalse(KeepInMemoryDecision.keepsByDefault(cubeBytes: 0, heldElsewhere: 0, physicalMemory: ram))
        // The same cube streams on a smaller Mac, by the same rule.
        XCTAssertFalse(KeepInMemoryDecision.keepsByDefault(cubeBytes: Int(3 * GB), heldElsewhere: 0, physicalMemory: 8 * GB))
        XCTAssertTrue(KeepInMemoryDecision.defaultReason(cubeBytes: Int(3 * GB), heldElsewhere: 0, physicalMemory: 8 * GB)
            .hasPrefix("Streaming: "))
        XCTAssertTrue(KeepInMemoryDecision.defaultReason(cubeBytes: Int(1 * GB), heldElsewhere: 0, physicalMemory: 8 * GB)
            .hasPrefix("Kept in memory: "))
    }

    /// Mutation: `activate` ignoring `keepInMemory` (never requesting `.resident`), or the default rule not applied.
    func testActivateKeepsBySwitchOrRuleAndSaysWhy() async throws {
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        let on = AppState()
        await on.activate(descriptor: descriptor, reader: reader,
                          runInitialAnalysis: false, keepInMemory: true)
        XCTAssertEqual(on.residency.mode, .resident)
        XCTAssertTrue(on.residency.isResident)
        XCTAssertEqual(on.residency.reason, "Kept in memory: Keep in memory was on when it was opened.")

        let off = AppState()
        await off.activate(descriptor: descriptor, reader: DemoFourDDataSource(),
                           runInitialAnalysis: false, keepInMemory: false)
        XCTAssertEqual(off.residency.mode, .streamed)
        XCTAssertFalse(off.residency.isResident)
        XCTAssertEqual(off.residency.reason, "Streaming: Keep in memory was off when it was opened.")

        // No choice (a Finder open): the rule. The tiny demo cube fits, so it is held, and the inspector says why.
        let byRule = AppState()
        await byRule.activate(descriptor: descriptor, reader: DemoFourDDataSource(), runInitialAnalysis: false)
        XCTAssertTrue(byRule.residency.isResident)
        XCTAssertTrue(byRule.residency.reason?.hasPrefix("Kept in memory: ") == true, byRule.residency.reason ?? "nil")
        // And another window counts what this one holds.
        let other = AppState()
        // At least these two (other tests' windows may still be alive in the same process).
        XCTAssertGreaterThanOrEqual(other.residency.bytesHeldElsewhere(),
                                    on.residency.byteCount + byRule.residency.byteCount)
        XCTAssertGreaterThan(on.residency.byteCount, 0)
        _ = on; _ = off
    }
}
