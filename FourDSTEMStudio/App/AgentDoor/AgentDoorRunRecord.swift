//
//  AgentDoorRunRecord.swift
//  Role: the runs the agent door starts (issue #330). A door tool answers before its run ends (tool handlers are synchronous),
//        so each run gets a `run_id` in the answer and get_window's `operation.last_run` says when that run finished, whether
//        it failed and why, and which disk detection settings it moved. A script waits for `finished_run_id` to reach its id
//        instead of guessing from `busy`, which is false for a moment before a run begins and after a quick one ends.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// One run the door started, as `operation.last_run` reports it.
struct AgentRunRecord {
    let id: Int
    let name: String
    let startedAt: Date
    var finished = false
    var finishedAt: Date?
    var error: String?
    /// The status line when the run ended: what the person reads (a cancel or a refusal says so there).
    var statusLine: String?
    /// "name old → new" for each disk detection setting the run moved (issue #232's line, as data).
    var diskChanges: [String: [String: Double]] = [:]

    var json: [String: Any] {
        [
            "run_id": id,
            "name": name,
            "state": !finished ? "running" : (error == nil ? "finished" : "failed"),
            "error": AgentJSON.orNull(error),
            "status_line": AgentJSON.orNull(statusLine),
            "changed_disk_settings": diskChanges,
            "seconds": AgentJSON.number(finishedAt.map { $0.timeIntervalSince(startedAt) }),
        ]
    }
}

extension AppState {
    /// Starts `work` as a door run named `name` and answers its id at once; `operation.last_run` follows it to its end.
    @discardableResult
    func agentRun(_ name: String, _ work: @escaping @MainActor () async -> Void) -> Int {
        agentRunSerial += 1
        let id = agentRunSerial
        agentLastRun = AgentRunRecord(id: id, name: name, startedAt: Date())
        let before = diskDetection.diskParams
        let errorBefore = errorMessage
        lastComputeFailure = nil
        Task { @MainActor [weak self] in
            await work()
            guard let self else { return }
            self.agentFinishedRunID = max(self.agentFinishedRunID ?? 0, id)
            guard self.agentLastRun?.id == id else { return }   // a later run took last_run; finished_run_id still counts it
            var record = self.agentLastRun!
            record.finished = true
            record.finishedAt = Date()
            let newError = self.errorMessage != errorBefore ? self.errorMessage : nil
            record.error = self.lastComputeFailure ?? newError
            record.statusLine = self.statusText
            record.diskChanges = Mac4DSTEMAgentDoor.diskChanges(from: before, to: self.diskDetection.diskParams)
            self.agentLastRun = record
        }
        return id
    }
}
