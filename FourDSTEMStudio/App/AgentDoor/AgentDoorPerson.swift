//
//  AgentDoorPerson.swift
//  Role: The agent door's tools for controls that were the person's alone (issue #297, Paul 13 Nov: "the mcp should be able to do
//        that as well"): Settings read and set, Clear Calibration, Remove Fine-Tuned Model, Reopen Without This Session, Release
//        cube and Try Demo Data. Each calls what its control calls and writes an Output line that starts "An agent".
//
//  What stays the person's, on purpose: the agents switches and the Agent folder (the door must not widen its own rights), Reset
//  All Settings (it would reset those switches too), and API keys (none passes through the door). Reopen Without This Session
//  raises the window's own question, as the button does; the person answers it, because the reopen can lose unsaved results.
//  The ones whose control asks first (Clear Calibration's dialog; Remove Fine-Tuned Model; Try Demo Data over an open dataset,
//  which the window offers only with none open) refuse in words what would be lost until the call carries confirm true, given
//  only after the person said yes in the chat (the dialog's question asked there, the standard confirm-to-proceed pattern).
//

import Foundation
import ShellAgentDoor
import ShellMetal
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    /// The `confirm` a tool that throws work away takes: true only once the person said yes in the chat.
    static let confirmParameter = AgentParameter("confirm", .boolean,
        summary: "true only after the person said yes in the chat to what the refusal says will be lost.")

    /// The refusal a tool that throws work away answers until the call confirms.
    static func needsConfirmation(_ loss: String) -> AgentToolOutput {
        .refusal(status: 409, message: loss + " Ask the person in the chat; if they say yes, call again with confirm true.")
    }

    static let personTools: [AgentTool] = [
        AgentTool(name: "get_settings", title: "Settings",
                  summary: "\(AppName.display)'s Settings as the window shows them: General (open behaviour, keep awake, figure size and "
                      + "format), Appearance (theme, colormaps, intensity display, scale bar), Analysis (the learned detector "
                      + "offer, the model caches' sizes) and Agents (whether runs and saves are allowed, the Agent folder's name). "
                      + "set_settings changes the analysis and display ones.",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            return .json(settingsSnapshot(state.preferences))
        },
        AgentTool(name: "set_settings", title: "Change settings",
                  summary: "Changes Settings, as their pickers and switches do; only the ones given. They are app-wide and kept, so "
                      + "say so to the person. The agents switches, the Agent folder and Reset All Settings stay the person's.",
                  input: .window,
                  parameters: SettingSpec.all.map(\.parameter),
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            let preferences = state.preferences
            for spec in SettingSpec.all {
                guard let text = call.arguments[spec.parameter.name] else { continue }
                guard spec.write(text, preferences) else {
                    return .refusal(status: 400, message: "\(spec.parameter.name) takes \(spec.choices.joined(separator: ", ")).")
                }
            }
            state.statusText = agentChangeLine("Settings", call.arguments)
            return .json(settingsSnapshot(preferences))
        },
        AgentTool(name: "clear_calibration", title: "Clear Calibration",
                  summary: "Returns every calibration value (origin and probe, ellipse, R–Q rotation, Q and R pixel sizes) to Not "
                      + "set, as Clear Calibration does, without reloading; the voltage stays. The orientation map, parallax "
                      + "alignment and ptychography made with them are discarded; strain and phase maps stay and should be rerun. "
                      + "Clear Calibration asks the person first, so this needs confirm true after the person said yes.",
                  input: .window, parameters: [confirmParameter], acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.agentBusy else { return busyRefusal }
            guard state.calibrationSession.hasAnyCalibrationValue else {
                return .refusal(status: 409, message: "There is no calibration value to clear.")
            }
            guard call.arguments["confirm"] == "true" else {
                return needsConfirmation("Clear Calibration returns origin and probe, ellipse, R–Q rotation and the Q and R pixel "
                    + "sizes to Not set, and discards the orientation map, parallax alignment and ptychography made with them; "
                    + "it cannot be undone except by calibrating again.")
            }
            state.clearCalibrationAndRecord()
            state.statusText = "An agent cleared the calibration."
            return .json(["cleared": true, "calibration": state.agentSnapshot()["calibration"] ?? NSNull()])
        },
        AgentTool(name: "remove_learned_model", title: "Remove Fine-Tuned Model",
                  summary: "Moves the active fine-tuned detector model to the Trash and makes the bundled model active again, as "
                      + "Remove Fine-Tuned Model does. Results made with it keep their record of which model made them. "
                      + "Needs confirm true after the person said yes.",
                  input: .window, parameters: [confirmParameter], acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.agentBusy else { return busyRefusal }
            guard let model = state.learnedDetection.activeModel else {
                return .refusal(status: 409, message: "No fine-tuned model is active; the bundled model is in use.")
            }
            guard let sha = model.sha256 else {
                return .refusal(status: 409, message: "No fine-tuned model is active; the bundled model is in use.")
            }
            guard call.arguments["confirm"] == "true" else {
                return needsConfirmation("Remove Fine-Tuned Model moves the active fine-tuned model (\(sha.prefix(8))) to the Trash; "
                    + "detection uses the bundled model from then on.")
            }
            state.removeActiveFineTunedModel()
            guard state.learnedDetection.activeModel?.sha256 != sha else {
                return .refusal(status: 500, message: "The model could not be moved to the Trash: \(state.statusText)")
            }
            state.statusText = "An agent moved the fine-tuned model to the Trash: " + state.statusText
            return .json(["removed": String(sha.prefix(8)), "active": "bundled"])
        },
        AgentTool(name: "reopen_without_session", title: "Reopen Without This Session",
                  summary: "Asks the person whether to reopen the dataset without restoring its saved session, as Reopen Without "
                      + "This Session does: the window shows the question and the person answers, since results not saved to the "
                      + "session go with the reopen. The session file stays on disk. get_window says when the dataset is back.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.agentBusy else { return busyRefusal }
            guard let saved = state.sessionLoadSpecification, saved != state.loadedView.specification else {
                return .refusal(status: 409, message: "The view on screen is the one the session restored; there is nothing to "
                    + "reopen without it.")
            }
            state.reopenIgnoringSessionSidecar()
            guard state.sessionSidecar.confirmsIgnore else {
                return .refusal(status: 409, message: "The current dataset has no recorded reopen path.")
            }
            state.statusText = "An agent asked to reopen without the session; the window asks the person."
            return .json(["asked_person": true])
        },
        AgentTool(name: "release_cube", title: "Release cube",
                  summary: "Lets go of the dataset kept in memory, as Release cube does; the file is read from disk again from "
                      + "then on. Nothing computed is lost.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.agentBusy else { return busyRefusal }
            guard state.residency.isResident else {
                return .refusal(status: 409, message: "The dataset is not kept in memory.")
            }
            state.statusText = "An agent released the cube from memory."
            Task { await state.releaseResidentCube() }
            return .json(["releasing": true])
        },
        AgentTool(name: "open_demo", title: "Try Demo Data",
                  summary: "Opens the demo, a small synthetic 4D-STEM dataset on which every workspace works, as Try Demo Data does, "
                      + "replacing the dataset the window shows. Nothing on disk is touched. get_window says when it is in. With a "
                      + "dataset open it needs confirm true after the person said yes, since what is not saved goes with it.",
                  input: .window, parameters: [confirmParameter], acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            if let refusal = openRefusal(state) { return refusal }
            if let open = state.descriptor, call.arguments["confirm"] != "true" {
                return needsConfirmation("The demo replaces \(open.fileName) in this window; results not saved to its session "
                    + "are lost.")
            }
            state.statusText = "An agent opened the demo data."
            let id = state.agentRun("open_demo") { await state.openDemoFixture() }
            return .json(["opening": "demo", "run_id": id])
        },
    ]

    /// Settings as `get_settings` answers them.
    static func settingsSnapshot(_ preferences: AppPreferences) -> [String: Any] {
        var values: [String: Any] = [:]
        for spec in SettingSpec.all { values[spec.parameter.name] = spec.read(preferences) }
        return [
            "settings": values,
            "agents": [
                "runs_allowed": preferences.agentRunsEnabled,
                "saves_allowed": preferences.agentFolderSavesEnabled,
                "agent_folder": AgentJSON.orNull(folder.url?.lastPathComponent),
                "agent_folder_problem": AgentJSON.orNull(folder.url == nil && preferences.agentFolderBookmark != nil
                    ? "The chosen folder is not open." : nil),
            ] as [String: Any],
            "kept_by_the_person": ["the agents switches", "the Agent folder", "Reset All Settings", "Clear Recent Datasets"],
        ]
    }

    /// One Settings control an agent may set, by the name the door gives it.
    struct SettingSpec {
        let parameter: AgentParameter
        let choices: [String]
        let read: (AppPreferences) -> Any
        /// false: the text is not one of the choices.
        let write: (String, AppPreferences) -> Bool

        private static func choice<T: RawRepresentable & CaseIterable>(
            _ name: String, _ summary: String, _ path: ReferenceWritableKeyPath<AppPreferences, T>
        ) -> SettingSpec where T.RawValue == String {
            let names = T.allCases.map(\.rawValue)
            return SettingSpec(parameter: AgentParameter(name, .choice(names), summary: summary), choices: names,
                               read: { $0[keyPath: path].rawValue },
                               write: { text, preferences in
                                   guard let value = T(rawValue: text) else { return false }
                                   preferences[keyPath: path] = value
                                   return true
                               })
        }

        private static func flag(_ name: String, _ summary: String, _ path: ReferenceWritableKeyPath<AppPreferences, Bool>) -> SettingSpec {
            SettingSpec(parameter: AgentParameter(name, .boolean, summary: summary), choices: ["true", "false"],
                        read: { $0[keyPath: path] },
                        write: { text, preferences in
                            guard text == "true" || text == "false" else { return false }
                            preferences[keyPath: path] = text == "true"
                            return true
                        })
        }

        static let all: [SettingSpec] = [
            choice("open_behaviour", "General: what Open Dataset… does.", \.openBehaviour),
            flag("keep_awake", "General: keep the Mac awake during long runs.", \.keepAwake),
            choice("export_scale", "General: figure image size (1x, 2x, 3x pixels).", \.exportScale),
            choice("figure_format", "General: figure format.", \.figureFormat),
            choice("appearance", "Appearance: light, dark or the system's.", \.appearance),
            choice("map_colormap", "Appearance: default colormap for maps.", \.mapColormap),
            choice("diffraction_colormap", "Appearance: default colormap for diffraction patterns.", \.diffractionColormap),
            choice("intensity_display", "Appearance: intensity display of patterns.", \.intensityDisplay),
            flag("show_scale_bar", "Appearance: show the scale bar.", \.showScaleBar),
            flag("offer_learned_detector", "Analysis: offer the learned (neural net) detector.", \.offerLearnedDetector),
        ]
    }
}
