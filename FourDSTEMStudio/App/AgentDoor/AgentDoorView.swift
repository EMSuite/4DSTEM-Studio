//
//  AgentDoorView.swift
//  Role: The agent door's view tool (issue #297): an agent sets what the person sees, so its reading of the screen matches
//        theirs: each image pane's zoom (View > Zoom In, Zoom Out, Zoom to Fit), the result's display orientation and mirror,
//        the pattern's fit overlay, and the comparison's Same scale. Nothing here changes a number or a result.
//
//  The panes keep their zoom as their own state (`PaneZoomModel`) and lend it to the window while they are on screen
//  (`AgentPaneZooms`), so a pane that goes away takes its zoom with it, as before.
//

import Foundation
import ShellAgentDoor
import ShellControls
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The zoom of each image pane on screen, held weakly: the pane owns it.
@MainActor
final class AgentPaneZooms {
    weak var pattern: PaneZoomModel?
    weak var result: PaneZoomModel?
    weak var comparison: PaneZoomModel?

    func model(_ pane: String) -> PaneZoomModel? {
        switch pane {
        case "pattern": pattern
        case "result": result
        case "comparison": comparison
        default: nil
        }
    }

    /// Each pane on screen and its zoom (1 is fitted to the pane).
    var summary: [String: Any] {
        var out: [String: Any] = [:]
        for (name, model) in [("pattern", pattern), ("result", result), ("comparison", comparison)] {
            out[name] = model.map { AgentJSON.number(Double($0.state.effectiveZoom)) } ?? NSNull()
        }
        return out
    }
}

extension Mac4DSTEMAgentDoor {
    static let viewTools: [AgentTool] = [
        AgentTool(name: "set_view", title: "View",
                  summary: "Sets what the window shows, as the view controls do; only what is given; nothing computed changes. "
                      + "zoom (fit, in, out: View > Zoom) acts on one pane (pane: pattern, result or comparison; it must be on "
                      + "screen), about its centre, a factor of 2 a step. orientation and mirrored turn the result's display (display "
                      + "only, not the R–Q rotation); fit_overlay shows the fitted ellipse or origin on the pattern; same_scale puts "
                      + "the comparison's A and B on one colour range. Answers the view as get_window's view.display says it.",
                  input: .window,
                  parameters: [
                      AgentParameter("pane", .choice(["pattern", "result", "comparison"]), summary: "The pane zoom acts on."),
                      AgentParameter("zoom", .choice(["fit", "in", "out"]), summary: "Zoom to Fit, Zoom In or Zoom Out."),
                      AgentParameter("orientation", .choice(RealSpaceDisplayOrientation.allCases.map { String(Int($0.degrees)) }),
                                     summary: "The result's display rotation, degrees."),
                      AgentParameter("mirrored", .boolean, summary: "Mirror the result's display horizontally."),
                      AgentParameter("fit_overlay", .boolean, summary: "Draw the calibration fit over the pattern."),
                      AgentParameter("same_scale", .boolean, summary: "The comparison's A and B on one colour range."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            let a = call.arguments
            if let zoom = a["zoom"] {
                guard let pane = a["pane"] else { return .refusal(status: 400, message: "zoom needs pane: pattern, result or comparison.") }
                guard let model = state.paneZooms.model(pane) else {
                    return .refusal(status: 409, message: "The \(pane) pane is not on screen in this window.")
                }
                model.pointer = nil   // about the centre, as the menu chosen with the mouse does
                switch zoom {
                case "in": model.zoomIn()
                case "out": model.zoomOut()
                default: model.fit()
                }
            }
            if let degrees = a["orientation"] {
                guard let orientation = RealSpaceDisplayOrientation.allCases.first(where: { String(Int($0.degrees)) == degrees }) else {
                    return .refusal(status: 400, message: "orientation is 0, 90, 180 or 270.")
                }
                state.realSpaceDisplayOrientation = orientation
            }
            if let mirrored = a["mirrored"] { state.realSpaceDisplayMirrored = mirrored == "true" }
            if let overlay = a["fit_overlay"] { state.showFitOverlay = overlay == "true" }
            if let same = a["same_scale"] { state.comparisonSameScale = same == "true" }
            state.statusText = agentChangeLine("the view", a)
            return .json(state.agentDisplay)
        },
    ]
}

extension AppState {
    /// The view as the person sees it, for get_window's view.display and set_view's answer.
    var agentDisplay: [String: Any] {
        [
            "zoom": paneZooms.summary,
            "orientation_degrees": Int(realSpaceDisplayOrientation.degrees),
            "mirrored": realSpaceDisplayMirrored,
            "fit_overlay": showFitOverlay,
            "same_scale": comparisonSameScale,
        ]
    }
}
