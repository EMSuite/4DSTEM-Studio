//
//  PrecipitateVariantRows.swift
//  Role: the variant block of the Precipitates section (suite task 40, design 2026-10-22 §3): the switch, the phase that has the orientation
//        relationship to the matrix, the relationship, the angle tolerance and agreement floor, the colour scheme of the glyphs, and the
//        legend (three needle directions, the twelve variants, the unassigned, the arithmetic). Every number is the report's
//        (`PrecipitateObjectReport.variantGroups`); this view computes nothing. Settings are recorded on the objects run (lineage).
//

import ShellInspector
import ShellLayout
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
#endif

struct PrecipitateVariantRows: View {
    @Environment(AppState.self) private var appState
    let report: PrecipitateObjectReport

    private var settings: VariantSettings? { appState.precipitateVariantSettings }

    var body: some View {
        @Bindable var appState = appState
        Toggle("Count variants", isOn: Binding(
            get: { appState.precipitateVariantSettings != nil },
            set: { appState.setPrecipitateVariantSettings($0 ? VariantSettings() : nil) }))
            .help("Name each object's orientation-relationship variant from the phase map's winning orientation per position, "
                  + "and count the precipitates per habit direction and per variant. The relationship is the one you type or pick.")
            .accessibilityIdentifier("precipitates.variants.section")
        if let settings {
            controls(settings)
            if let warning = report.variantWarning {
                InspectorWarning(warning).accessibilityIdentifier("precipitates.variants.warning")
            }
            if let why = report.variantUnavailable {
                InspectorNote(why).accessibilityIdentifier("precipitates.variants.unavailable")
            } else if let groups = report.variantGroups {
                legend(groups)
            }
        }
    }

    // MARK: settings

    @ViewBuilder private func controls(_ settings: VariantSettings) -> some View {
        @Bindable var appState = appState
        let candidates = appState.phaseMapping.map?.phaseNames.enumerated().filter { $0.offset != appState.phaseMapping.map?.matrixPhaseIndex }.map(\.element) ?? []
        if candidates.count > 1 {
            InspectorRow("Phase") {
                Picker("Phase", selection: Binding(get: { settings.phaseName ?? candidates.first ?? "" },
                                                   set: { update({ s, v in s.phaseName = v }, with: $0) })) {
                    ForEach(candidates, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .accessibilityIdentifier("precipitates.variants.phase")
            }
        }
        VariantRelationshipFields(relationship: settings.relationship) { relationship in
            update({ s, v in s.relationship = v }, with: relationship)
        }
        InspectorRow("Angle tolerance") {
            OptionalNumericField(title: "Angle tolerance", value: settings.toleranceDegrees, format: .number, unit: "°",
                                 prompt: (appState.phaseMapping.reference.inPlaneStepDeg / 2).formatted()) { value in
                update({ s, v in s.toleranceDegrees = v }, with: value)
            }
            .accessibilityIdentifier("precipitates.variants.tolerance")
        }
        .help("A pixel votes for a variant only when its orientation lies this near it. Empty: half the library's in-plane step, because no pixel can say more than its grid does.")
        InspectorRow("Agreement ≥") {
            OptionalNumericField(title: "Agreement", value: settings.agreementMinimum, format: .number, prompt: "0.5") { value in
                update({ s, v in s.agreementMinimum = min(max(v ?? 0.5, 0.01), 1) }, with: value)
            }
            .accessibilityIdentifier("precipitates.variants.agreement")
        }
        .help("The least share of an object's pixels that must vote for the winning variant; below it the object is unassigned, never forced into one.")
        InspectorRow("Colour by") {
            Picker("Colour by", selection: $appState.precipitateOverlay.colourBy) {
                ForEach(PrecipitateColourBy.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()   // a menu: the segmented control is wider than the narrowest inspector column
            .accessibilityIdentifier("precipitates.variants.colourBy")
        }
    }

    /// One setting changed: the whole value goes back through `setPrecipitateVariantSettings` (it records the run and recomputes).
    private func update<T>(_ change: @escaping (inout VariantSettings, T) -> Void, with value: T) {
        guard var next = appState.precipitateVariantSettings else { return }
        change(&next, value)
        appState.setPrecipitateVariantSettings(next)
    }

    // MARK: legend

    @ViewBuilder private func legend(_ groups: [PrecipitateObjectReport.VariantGroup]) -> some View {
        let directions = report.variantDirections ?? []
        ForEach(groups.filter { $0.kind == .direction }) { g in
            row(g, swatch: VariantPalette.rgb(direction: g.index),
                suffix: report.endOnDirection == g.index ? (report.variantHabit == .plate ? "face-on" : "end-on") : nil)
                .accessibilityIdentifier("precipitates.variants.legend.direction.\(g.index)")
        }
        DisclosureGroup("Variants") {
            ForEach(groups.filter { $0.kind == .variant }) { g in
                let d = directions.indices.contains(g.index - 1) ? directions[g.index - 1] : 0
                row(g, swatch: VariantPalette.rgb(direction: d, rank: VariantPalette.rank(variant: g.index, directions: directions)),
                    suffix: groups.first { $0.kind == .direction && $0.index == d }?.title ?? VariantGroupText.directionName(d))
                    .accessibilityIdentifier("precipitates.variants.legend.variant.\(g.index)")
            }
        }
        .accessibilityIdentifier("precipitates.variants.legend")
        if let u = groups.first(where: { $0.kind == .unassigned }) {
            row(u, swatch: VariantPalette.unassigned, suffix: u.detail)
                .accessibilityIdentifier("precipitates.variants.legend.unassigned")
        }
        InspectorNote(VariantGroupText.totals(groups)).accessibilityIdentifier("precipitates.variants.totals")
        if let summary = report.variantSummary {
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ g: PrecipitateObjectReport.VariantGroup, swatch: VariantPalette.RGB, suffix: String?) -> some View {
        InspectorDataRow(g.title) {
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: swatch.r, green: swatch.g, blue: swatch.b)).frame(width: LayoutPolicy.legendSwatch, height: LayoutPolicy.legendSwatch)
                        .accessibilityHidden(true)
                    Text("\(g.countedObjects) object\(g.countedObjects == 1 ? "" : "s")").monospacedDigit()
                }
                if let areal = g.arealDensity, let unit = report.pixelUnit {
                    Text(PrecipitateFormat.density(areal, unit: unit)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let suffix { Text(suffix).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(g.title), \(g.countedObjects) objects")
    }
}

/// The legend's words, pure so a test holds them.
nonisolated enum VariantGroupText {
    static func directionName(_ i: Int) -> String { PrecipitateObjectReport.VariantGroup.directionName(i) }

    /// "22 assigned + 3 unassigned = 25 counted": the arithmetic the legend adds up to (counted objects the variant run covered).
    static func totals(_ groups: [PrecipitateObjectReport.VariantGroup]) -> String {
        let assigned = groups.filter { $0.kind == .direction }.reduce(0) { $0 + $1.countedObjects }
        let unassigned = groups.first { $0.kind == .unassigned }?.countedObjects ?? 0
        return "\(assigned) assigned + \(unassigned) unassigned = \(assigned + unassigned) counted."
    }
}

/// The relationship as a paper states it (#512): two parallel pairs in one field, the habit and its axis, committed on Return once
/// all three are there. Empty until the person types one: no built-in relationship is offered, for any material (a session saved
/// with one of the three Al relationships of 5.4 replays it, and its note names the paper). A field that does not read is named
/// and the standing relationship stays.
private struct VariantRelationshipFields: View {
    let relationship: VariantRelationship?
    let commit: (VariantRelationship?) -> Void
    @State private var pairs = ""
    @State private var habit: OrientationRelationshipPreset.Habit?
    @State private var axis = ""
    @State private var refusal: String?

    var body: some View {
        InspectorRow("Relationship") {
            TextField("Relationship", text: $pairs, prompt: Text("(h k l) ∥ (h k l), [u v w] ∥ [u v w]"))
                .labelsHidden()
                .onSubmit(apply)
                .accessibilityIdentifier("precipitates.variants.orPairs")
        }
        .onChange(of: relationship, initial: true) { _, new in
            pairs = new?.pairs ?? ""
            habit = new?.habit
            axis = new?.habitAxisText ?? ""
            refusal = nil
        }
        .help("Two parallel pairs, the precipitate's first, as a paper states them: planes in ( ), directions in [ ]. The first pair is "
              + "kept exact, the second fixes the rotation about it (orix from_align_vectors). Return applies.")
        InspectorRow("Habit") {
            Picker("Habit", selection: Binding(get: { habit }, set: { habit = $0; apply() })) {
                Text("Choose").tag(OrientationRelationshipPreset.Habit?.none)
                Text("Needle").tag(OrientationRelationshipPreset.Habit?.some(.needle))
                Text("Plate").tag(OrientationRelationshipPreset.Habit?.some(.plate))
            }
            .labelsHidden().fixedSize()
            .accessibilityIdentifier("precipitates.variants.habit")
        }
        .help("A needle lies along its habit axis; a plate stands on it (the axis is its normal).")
        InspectorRow("Habit axis") {
            TextField("Habit axis", text: $axis, prompt: Text("[u v w]"))
                .labelsHidden()
                .onSubmit(apply)
                .accessibilityIdentifier("precipitates.variants.habitAxis")
        }
        .help("The needle axis or the plate normal, a direction of the precipitate.")
        if let example = relationship?.example {
            InspectorNote("\(example.precipitateName) in \(example.matrixName) as \(example.citation) state it.")
                .accessibilityIdentifier("precipitates.variants.exampleNote")
        }
        if let refusal {
            InspectorNote(refusal).accessibilityIdentifier("precipitates.variants.orRefusal")
        }
        if relationship != nil {
            InspectorActionRow {
                Button("Clear Relationship") { commit(nil) }
                    .accessibilityIdentifier("precipitates.variants.clearRelationship")
            }
        }
    }

    private func apply() {
        let typed = pairs.trimmingCharacters(in: .whitespacesAndNewlines), axisText = axis.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty && axisText.isEmpty && habit == nil {
            refusal = nil
            commit(nil)
            return
        }
        guard !typed.isEmpty, let habit, !axisText.isEmpty else {
            refusal = "Type the two pairs, choose the habit and type its axis; the relationship applies once all three are there."
            return
        }
        guard let parsed = PhaseMappingSlot.parseOrientationRelationships(typed), parsed.count == 2 else {
            refusal = VariantError.pairsDoNotRead(typed).localizedDescription
            return
        }
        guard let uvw = PhaseMappingSlot.parseZoneAxis(axisText), uvw != .zero else {
            refusal = "\(axisText) is not a direction [u v w]."
            return
        }
        refusal = nil
        let next = VariantRelationship(pairs: typed, habit: habit, habitAxis: uvw)
        // Return on a replayed example's own fields keeps it.
        if let current = relationship, current.pairs == next.pairs, current.habit == habit, current.habitAxis == uvw { return }
        commit(next)
    }
}
