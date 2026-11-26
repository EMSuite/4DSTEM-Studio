//
//  ObjectVariants.swift
//  Role: the orientation-relationship variant of each precipitate object (suite task 40, design 2026-10-22 §3): the phase map's winning
//        library entry per scan position (phase x zone axis x in-plane rotation) becomes an orientation, DiffractoKit's
//        `OrientationVariantSet.nearestVariant` names its variant (12 for beta'' in Al), and each object takes the variant most of its
//        pixels vote for. Pure: no SwiftUI, no AppState; the kit does the rotation algebra, this file votes and says why not.
//
//  What it is not: ACOM orientations are the second source behind the same seam and are not built (`VariantSettings.source`).
//  Checked against planted truth only: the variant set is planted, not a measured set.
//
//  Conventions (read from the kit, tested in ObjectVariantsTests): an entry's orientation is
//  `ZoneAxisFrame.matrix(detectorBasis(zoneAxis), inPlaneAngle)` of its zone axis in the crystal's own Cartesian frame (columns = the
//  detector x, y and the beam in crystal axes); the library rotates the projected vectors by +theta, which is the same matrix. The
//  precipitate-to-matrix rotation of a pixel is `M_matrix * M_precipitate^T` (`OrientationVariantSet.observedRelation`).
//

import Foundation
import simd
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DiffractoCore
import DiffractoOrientation
#endif

/// The three Al relationships of 5.4 (suite task 40), kept only so sessions and recipes saved with them replay with the same numbers
/// (#512): no menu or tool offers them, and nothing is chosen by default. beta'' is a needle; theta' and T1 are plates. Replayed on
/// another matrix, the block warns. A general set of classic relationships may come later, for any material.
package nonisolated enum OrientationRelationshipPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case betaDoublePrimeInAl = "beta-double-prime-in-al"
    case thetaPrimeInAl = "theta-prime-in-al"
    case t1InAl = "t1-in-al"

    /// What the precipitate looks like along its habit axis: a needle lies along it, a plate stands on it.
    package enum Habit: String, Codable, Sendable { case needle, plate }

    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .betaDoublePrimeInAl: "\u{03B2}\u{2033} in Al, Andersen 1998"
        case .thetaPrimeInAl: "\u{03B8}\u{2032} in Al, Thronsen 2024"
        case .t1InAl: "T1 in Al, Thronsen 2024"
        }
    }
    package var habit: Habit {
        switch self { case .betaDoublePrimeInAl: .needle; case .thetaPrimeInAl, .t1InAl: .plate }
    }
    /// The habit axis of the precipitate as lattice indices (a direction): the needle axis (b of the monoclinic cell for beta'', Andersen 1998:
    /// b ∥ Al <001>) or the plate normal (c of the tetragonal theta' cell, [0001] of the hexagonal T1 cell).
    package var habitAxis: SIMD3<Int> {
        switch self { case .betaDoublePrimeInAl: SIMD3(0, 1, 0); case .thetaPrimeInAl, .t1InAl: SIMD3(0, 0, 1) }
    }
    /// The matrix directions the habit axis can lie along, in the matrix's Cartesian frame (cubic Al: the lattice indices themselves), ±n
    /// being one family; `familyNames` names them in the same order. Cube axes for beta'' and theta', the four <111> normals for T1.
    package var habitFamilies: [SIMD3<Double>] {
        switch self {
        case .betaDoublePrimeInAl, .thetaPrimeInAl: [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        case .t1InAl: [SIMD3(1, 1, 1), SIMD3(-1, 1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, -1)]
        }
    }
    package var familyNames: [String] {
        switch self {
        case .betaDoublePrimeInAl, .thetaPrimeInAl: ["[100]", "[010]", "[001]"]
        case .t1InAl: ["[111]", "[-111]", "[1-11]", "[11-1]"]
        }
    }
    /// The two statements the rotation is built from (`OrientationRelationship.rotation`; the first fixes an axis exactly, the second the
    /// rotation about it). beta'': a ∥ [3 2 0] and b ∥ [0 0 1] of the matrix. theta' (Thronsen 2024): (001) ∥ (001) and [100] ∥ [100].
    /// T1: (0001) ∥ (111) and, with the kit's three-index direction u a1 + v a2 + w c, [2 1 0] (four-index [10-10]) ∥ [1 -1 0].
    package var statements: (OrientationRelationship, OrientationRelationship) {
        switch self {
        case .betaDoublePrimeInAl:
            (OrientationRelationship(candidate: .direction(SIMD3(1, 0, 0)), matrix: .direction(SIMD3(3, 2, 0))),
             OrientationRelationship(candidate: .direction(SIMD3(0, 1, 0)), matrix: .direction(SIMD3(0, 0, 1))))
        case .thetaPrimeInAl:
            (OrientationRelationship(candidate: .plane(SIMD3(0, 0, 1)), matrix: .plane(SIMD3(0, 0, 1))),
             OrientationRelationship(candidate: .direction(SIMD3(1, 0, 0)), matrix: .direction(SIMD3(1, 0, 0))))
        case .t1InAl:
            (OrientationRelationship(candidate: .plane(SIMD3(0, 0, 1)), matrix: .plane(SIMD3(1, 1, 1))),
             OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, -1, 0))))
        }
    }

    /// The paper, in the words a note under the relationship uses.
    package var citation: String {
        switch self {
        case .betaDoublePrimeInAl: "Andersen et al., Acta Mater. 46 (1998) 3283"
        case .thetaPrimeInAl, .t1InAl: "Thronsen et al. (2024)"
        }
    }
    /// The precipitate's name in the paper.
    package var precipitateName: String {
        switch self { case .betaDoublePrimeInAl: "\u{03B2}\u{2033}"; case .thetaPrimeInAl: "\u{03B8}\u{2032}"; case .t1InAl: "T1" }
    }
    /// The matrix the paper states the relationship for: aluminium, by its atomic number.
    package var matrixName: String { "Al" }
    package var matrixElements: Set<Int> { [13] }
    /// The two statements as the relationship field writes them: "[1 0 0] ∥ [3 2 0], [0 1 0] ∥ [0 0 1]".
    package var pairsText: String { [statements.0, statements.1].map(OrientationRelationshipVariants.text).joined(separator: ", ") }

    /// The family whose direction is most parallel to `axis` (largest |dot|, ±n one family), in `habitFamilies` order.
    package func family(nearest axis: SIMD3<Double>) -> Int { VariantSetup.family(nearest: axis, in: habitFamilies) }
    /// The family lying along `axis` (a beam direction) to within a tenth of a degree, or nil when it lies along none.
    package func family(alongBeam axis: SIMD3<Double>) -> Int? { VariantSetup.family(alongBeam: axis, in: habitFamilies) }

    /// The sentence the block and the door say when this example is used on a matrix the paper does not state it for; nil when the
    /// matrix is made of the paper's elements only.
    package func warning(matrix: CrystalStructure, matrixName shown: String) -> String? {
        let elements = Set(matrix.sites.map(\.z))
        guard elements.isEmpty || elements != matrixElements else { return nil }
        return "\(citation) state this relationship for \(precipitateName) in \(matrixName); the matrix here is \(shown). "
            + "Type the relationship a paper states for this matrix."
    }
}

/// The relationship whose variants are named (#512): two parallel pairs as a paper states them (orix `Misorientation.from_align_vectors`
/// builds a relationship from two such pairs; the kit's `OrientationRelationship.rotation` keeps the first exact), the habit (needle or
/// plate) and its axis as a direction of the precipitate (the needle axis or the plate normal). Typed by the person; a session saved
/// with a 5.4 Al relationship replays it as that example, with its own statements and matrix directions. Nothing is chosen until typed.
package nonisolated struct VariantRelationship: Codable, Hashable, Sendable {
    /// The pairs as typed, in the phase rows' grammar: "(0 0 1) ∥ (1 1 1), [2 1 0] ∥ [1 -1 0]".
    package let pairs: String
    package let habit: OrientationRelationshipPreset.Habit
    package let habitAxis: SIMD3<Int>
    /// The replayed 5.4 relationship it is, while nothing of it was changed.
    package let example: OrientationRelationshipPreset?

    package init(pairs: String, habit: OrientationRelationshipPreset.Habit, habitAxis: SIMD3<Int>) {
        self.pairs = pairs.trimmingCharacters(in: .whitespacesAndNewlines); self.habit = habit; self.habitAxis = habitAxis; example = nil
    }

    package init(example: OrientationRelationshipPreset) {
        pairs = example.pairsText; habit = example.habit; habitAxis = example.habitAxis; self.example = example
    }

    /// The two statements: the example's own, or the typed pairs when they read as exactly two.
    package var statements: (OrientationRelationship, OrientationRelationship)? {
        if let example { return example.statements }
        guard let parsed = PhaseMappingSlot.parseOrientationRelationships(pairs), parsed.count == 2 else { return nil }
        return (parsed[0], parsed[1])
    }

    /// "[u v w]" of the habit axis.
    package var habitAxisText: String { "[\(habitAxis.x) \(habitAxis.y) \(habitAxis.z)]" }

    /// The menu's and the summary's words: the example's title, or the pairs with the habit.
    package var title: String { example?.title ?? "\(pairs); \(habit.rawValue) along \(habitAxisText)" }
}

/// How objects are assigned to variants. Settings, not results: they ride in the sidecar and replay recomputes.
package nonisolated struct VariantSettings: Codable, Hashable, Sendable {
    /// Where the object's orientation comes from. Only the phase map's winning entries are built.
    package var source = "known_variants"
    /// None until the person types one (#512): the run then says what is missing.
    package var relationship: VariantRelationship?
    /// A pixel votes only when its nearest variant is this near (degrees); nil is half the library's in-plane step, because no pixel
    /// can say more than its grid does.
    package var toleranceDegrees: Double?
    /// The least share of the object's pixels that must vote for the winning variant.
    package var agreementMinimum = 0.5
    /// The phase that has the relationship to the matrix (a candidate phase's display name); nil is the first candidate.
    package var phaseName: String?
    package init() {}
    /// Counting with a 5.4 relationship, as a replayed session does.
    package init(example: OrientationRelationshipPreset) { relationship = VariantRelationship(example: example) }

    // MARK: lineage parameters (the sidecar's record of it; settings, not results: replay recomputes)

    package static let keys = ["variant_source", "variant_or", "variant_or_pairs", "variant_habit", "variant_habit_axis", "variant_phase",
                               "variant_tolerance_deg", "variant_agreement_min"]

    /// `variant_or`: an example's raw value (the three values sessions from before #512 carry, replayed unchanged), "typed" with the
    /// pairs, the habit and its axis beside it, or "none".
    package var parameters: [String: String] {
        var p = ["variant_source": source, "variant_agreement_min": String(agreementMinimum)]
        switch relationship {
        case nil: p["variant_or"] = "none"
        case let r? where r.example != nil: p["variant_or"] = r.example?.rawValue
        case let r?:
            p["variant_or"] = "typed"
            p["variant_or_pairs"] = r.pairs
            p["variant_habit"] = r.habit.rawValue
            p["variant_habit_axis"] = "\(r.habitAxis.x) \(r.habitAxis.y) \(r.habitAxis.z)"
        }
        if let toleranceDegrees { p["variant_tolerance_deg"] = String(toleranceDegrees) }
        if let phaseName { p["variant_phase"] = phaseName }
        return p
    }

    package init?(parameters p: [String: String]) {
        guard let or = p["variant_or"] else { return nil }
        self.init()
        source = p["variant_source"] ?? "known_variants"
        if let example = OrientationRelationshipPreset(rawValue: or) {
            relationship = VariantRelationship(example: example)
        } else if or == "typed", let pairs = p["variant_or_pairs"], let habit = p["variant_habit"].flatMap(OrientationRelationshipPreset.Habit.init(rawValue:)),
                  let axis = p["variant_habit_axis"].flatMap(PhaseMappingSlot.parseZoneAxis) {
            relationship = VariantRelationship(pairs: pairs, habit: habit, habitAxis: axis)
        }
        agreementMinimum = p["variant_agreement_min"].flatMap(Double.init) ?? 0.5
        toleranceDegrees = p["variant_tolerance_deg"].flatMap(Double.init)
        phaseName = p["variant_phase"]
    }
}

/// One object's variant, or why it has none.
package nonisolated struct VariantAssignment: Codable, Hashable, Sendable {
    package enum Status: Codable, Hashable, Sendable {
        case assigned
        /// The reason, in words.
        case ambiguous(String)
        case noOrientation
    }
    /// 1...12 in the kit's order; nil unless assigned.
    package let variant: Int?
    /// Which of the preset's matrix directions the habit axis lies along (index into `familyNames`: 0, 1, 2 for [100], [010], [001] for beta''); nil unless assigned.
    package let direction: Int?
    /// That direction's name ("[100]"); nil unless assigned, and in a snapshot from before the presets (the cube axes then).
    package let directionName: String?
    /// Mean angle from the voting pixels' orientations to the variant, degrees.
    package let angleDegrees: Double?
    /// The share of the object's pixels that voted for the winning variant.
    package let agreement: Double
    package let status: Status

    /// The other variants the pattern cannot tell from `variant` (1...12, ascending): they predict the same spots within the detector's
    /// reach at this matrix orientation (DiffractoKit `indistinguishableVariants`), as the two variants of a needle lying in the foil plane
    /// do. `variant` is then the smallest of the group. nil when the variant stands alone, and in a snapshot from before this was known.
    package var alternatives: [Int]? = nil

    package var isAssigned: Bool { status == .assigned }
    package init(variant: Int?, direction: Int?, directionName: String? = nil, angleDegrees: Double?, agreement: Double, status: Status,
                 alternatives: [Int]? = nil) {
        self.variant = variant; self.direction = direction; self.directionName = directionName; self.angleDegrees = angleDegrees
        self.agreement = agreement; self.status = status; self.alternatives = alternatives
    }
    /// "6", or "6 or 7" for a group the pattern cannot tell apart; "" unless assigned.
    package var variantText: String {
        guard let variant else { return "" }
        return ([variant] + (alternatives ?? [])).map(String.init).joined(separator: " or ")
    }
}

/// The kit's variant set for one precipitate in one matrix, with the matrix direction each variant's habit axis lies along.
package nonisolated struct VariantSetup: Sendable {
    package let set: OrientationVariantSet
    /// Per variant (kit order): the index into `familyNames` of the matrix direction its habit axis (needle axis or plate normal) lies along.
    package let habitFamily: [Int]
    /// The matrix directions the habit axis lies along, in the matrix's Cartesian frame, ±n one family: an example's own (the cube axes,
    /// the four <111>), or for a typed relationship the distinct images of the habit axis over the variants, in the kit's variant order.
    package let habitFamilies: [SIMD3<Double>]
    /// Their names as matrix lattice directions ("[100]", "[-111]"), in the same order.
    package let familyNames: [String]
    package let relationship: VariantRelationship

    package init(precipitate: CrystalStructure, matrix: CrystalStructure, preset: OrientationRelationshipPreset) throws {
        try self.init(precipitate: precipitate, matrix: matrix, relationship: VariantRelationship(example: preset))
    }

    package init(precipitate: CrystalStructure, matrix: CrystalStructure, relationship: VariantRelationship) throws {
        guard let statements = relationship.statements else { throw VariantError.pairsDoNotRead(relationship.pairs) }
        guard let matrixSymmetry = PhaseModel.orientationSymmetry(of: matrix),
              let precipitateSymmetry = PhaseModel.orientationSymmetry(of: precipitate) else { throw VariantError.noStandardSetting }
        let relation: simd_double3x3
        do { relation = try OrientationRelationship.rotation(statements.0, statements.1, precipitate: precipitate, matrix: matrix) }
        catch { throw VariantError.pairsDoNotFixAnOrientation }
        set = try OrientationVariantSet(matrix: relation, matrixSymmetry: matrixSymmetry, precipitateSymmetry: precipitateSymmetry)
        guard let habit = PhaseReferenceLibrary.cartesianZoneAxis(relationship.habitAxis, crystal: precipitate) else {
            throw VariantError.habitAxisIsZero
        }
        if let example = relationship.example {
            habitFamilies = example.habitFamilies
            familyNames = example.familyNames
        } else {
            var families: [SIMD3<Double>] = []
            for v in set.variants {
                let axis = simd_normalize(v * habit)
                if !families.contains(where: { abs(simd_dot($0, axis)) > cos(0.5 * .pi / 180) }) { families.append(axis) }
            }
            habitFamilies = families
            familyNames = families.map { Self.directionName($0, in: matrix) }
        }
        let families = habitFamilies
        habitFamily = set.variants.map { Self.family(nearest: $0 * habit, in: families) }
        self.relationship = relationship
    }

    /// The family whose direction is most parallel to `axis` (largest |dot|, ±n one family), in `families` order.
    package static func family(nearest axis: SIMD3<Double>, in families: [SIMD3<Double>]) -> Int {
        let unit = simd_length(axis) > 0 ? simd_normalize(axis) : axis
        let dots = families.map { abs(simd_dot(simd_normalize($0), unit)) }
        return dots.indices.max { dots[$0] < dots[$1] } ?? 0
    }
    /// The family lying along `axis` (a beam direction) to within a tenth of a degree, or nil when it lies along none.
    package static func family(alongBeam axis: SIMD3<Double>, in families: [SIMD3<Double>]) -> Int? {
        guard simd_length(axis) > 0, !families.isEmpty else { return nil }
        let i = family(nearest: axis, in: families)
        return abs(simd_dot(simd_normalize(families[i]), simd_normalize(axis))) > cos(0.1 * .pi / 180) ? i : nil
    }
    package func family(alongBeam axis: SIMD3<Double>) -> Int? { Self.family(alongBeam: axis, in: habitFamilies) }

    /// A Cartesian direction of `crystal` as its smallest lattice indices, first non-zero index positive: "[100]", "[1-10]", "[2 10 1]".
    /// uᵢ = v · bᵢ (the reciprocal rows, aᵢ · bⱼ = δᵢⱼ), scaled by the least whole multiple up to 12 that makes them whole within 0.02;
    /// a direction no such multiple makes whole is written with two decimals.
    package static func directionName(_ v: SIMD3<Double>, in crystal: CrystalStructure) -> String {
        let b = crystal.cell.reciprocalLattice
        var u = SIMD3(simd_dot(v, b[0]), simd_dot(v, b[1]), simd_dot(v, b[2]))
        let largest = max(abs(u.x), abs(u.y), abs(u.z))
        guard largest.isFinite, largest > 0 else { return "[?]" }
        u /= largest
        if let first = [u.x, u.y, u.z].first(where: { abs($0) > 1e-6 }), first < 0 { u = -u }
        let smallest = [u.x, u.y, u.z].map(abs).filter { $0 > 1e-6 }.min() ?? 1
        for k in 1...12 {
            let scaled = u * (Double(k) / smallest)
            let whole = scaled.rounded(.toNearestOrAwayFromZero)
            if simd_reduce_max(simd_abs(scaled - whole)) < 0.02, simd_reduce_max(simd_abs(whole)) <= 99 {
                let ints = [Int(whole.x), Int(whole.y), Int(whole.z)]
                return "[" + ints.map(String.init).joined(separator: ints.allSatisfy { abs($0) < 10 } ? "" : " ") + "]"
            }
        }
        return "[" + [u.x, u.y, u.z].map { String(format: "%.2f", $0) }.joined(separator: " ") + "]"
    }
}

package nonisolated enum VariantError: Error, Equatable, LocalizedError {
    case noStandardSetting
    case noMatrixEntry
    /// No relationship is typed and no example picked (#512).
    case noRelationship
    /// The typed pairs are not two pairs of the grammar.
    case pairsDoNotRead(String)
    /// The pairs do not fix an orientation (a zero vector, parallel vectors on one side).
    case pairsDoNotFixAnOrientation
    case habitAxisIsZero
    package var errorDescription: String? {
        switch self {
        case .noStandardSetting: "A phase has no standard orientation setting, so its variants cannot be named."
        case .noMatrixEntry: "The phase map has no fitted matrix orientation to measure the variants from."
        case .noRelationship: "Type the orientation relationship as a paper states it: two parallel pairs, the habit and its axis."
        case .pairsDoNotRead(let text): "\"\(text)\" is not two parallel pairs: write them as (h k l) ∥ (h k l), [u v w] ∥ [u v w], "
            + "the precipitate first."
        case .pairsDoNotFixAnOrientation: "These pairs do not fix an orientation: each side needs two vectors that are not parallel."
        case .habitAxisIsZero: "The habit axis [0 0 0] is no direction."
        }
    }
}

package nonisolated enum ObjectVariantAssigner {

    /// The orientations of a library's entries and of the scan's matrix, in the kit's matrix convention.
    package nonisolated struct Orientations: Sendable {
        package var entryPhase: [Int]
        package var entryOrientation: [simd_double3x3?]
        package var matrixOrientation: simd_double3x3
        package var inPlaneStepDegrees: Double
        /// The matrix's own cube axis along the beam, when the matrix zone axis is one: the "end-on" direction of the cube-axis presets.
        package var matrixBeamDirection: Int?
        /// The beam as a unit vector in the matrix's Cartesian frame (the matrix entry's zone axis): the presets name the family along it.
        package var matrixBeamAxis: SIMD3<Double>?
        /// A map made from the structures (mac4DSTEM#245): the precipitate orientation found at each position (nil where the
        /// position is not this phase) and the matrix orientation there, in the grain's one frame (`canonicalMatrixFrame`).
        /// When set, the entries are not consulted.
        package var positionPrecipitate: [simd_double3x3?]?
        package var positionMatrix: [simd_double3x3?]?
        /// The variants grouped by what the pattern can tell apart (0-based indices, each group ascending), one grouping per beam direction
        /// met in the scan, and for each position the grouping that holds there (-1: none). Empty: every variant stands alone.
        package var groupings: [[[Int]]] = []
        package var positionGrouping: [Int] = []

        package init(entryPhase: [Int], entryOrientation: [simd_double3x3?], matrixOrientation: simd_double3x3, inPlaneStepDegrees: Double,
                     matrixBeamDirection: Int? = nil, matrixBeamAxis: SIMD3<Double>? = nil) {
            self.entryPhase = entryPhase; self.entryOrientation = entryOrientation; self.matrixOrientation = matrixOrientation
            self.inPlaneStepDegrees = inPlaneStepDegrees; self.matrixBeamDirection = matrixBeamDirection; self.matrixBeamAxis = matrixBeamAxis
        }

        /// From a run that found the orientations from the structures. `candidateIndex` counts the run's candidates from 0.
        /// The default tolerance set here is the kit's own angle within which two variants are one (3 degrees); the variant
        /// run adds the learned relationship's distance to the named one (`ObjectVariantJoin.learnedOffsetDegrees`).
        package static func make(structureRun run: StructurePhaseMapping, candidateIndex: Int, matrixCrystal: CrystalStructure) -> Orientations? {
            let verdicts = run.classification.verdicts
            guard verdicts.count == run.matrixOrientations.count else { return nil }
            let matrices: [simd_double3x3?] = run.matrixOrientations.map { $0.map { ObjectVariantAssigner.canonicalMatrixFrame($0, crystal: matrixCrystal) } }
            let precipitates: [simd_double3x3?] = verdicts.map { $0.verdict == .indexed && $0.phaseIndex == candidateIndex ? $0.orientation : nil }
            // The beam of most positions names the end-on direction; a scan of several grains has more than one and names none.
            var beams: [SIMD3<Int>: Int] = [:]
            for m in matrices { if let b = m?.columns.2 { beams[SIMD3(Int((b.x * 100).rounded()), Int((b.y * 100).rounded()), Int((b.z * 100).rounded())), default: 0] += 1 } }
            let total = beams.values.reduce(0, +)
            var beamAxis: SIMD3<Double>?
            if let top = beams.max(by: { $0.value < $1.value }), 10 * top.value >= 9 * total {
                beamAxis = simd_normalize(SIMD3(Double(top.key.x), Double(top.key.y), Double(top.key.z)))
            }
            let beam = beamAxis.flatMap { axis -> Int? in
                let m = (0..<3).max { abs(axis[$0]) < abs(axis[$1]) } ?? 0
                return abs(abs(axis[m]) - 1) < 1e-3 ? m : nil
            }
            var out = Orientations(entryPhase: [], entryOrientation: [], matrixOrientation: matrix_identity_double3x3,
                                   inPlaneStepDegrees: 2 * LearnedOrientationRelationship.defaultVariantMergeAngleRad * 180 / .pi,
                                   matrixBeamDirection: beam, matrixBeamAxis: beamAxis)
            out.positionPrecipitate = precipitates
            out.positionMatrix = matrices
            return out
        }

        /// From the phase map's library and its matrix entry. Nil without a matrix entry.
        package static func make(library: PhaseReferenceLibrary, matrixEntryIndex: Int) -> Orientations? {
            guard library.entries.indices.contains(matrixEntryIndex) else { return nil }
            func orientation(_ entry: PhaseOrientationReference) -> simd_double3x3? {
                guard library.phases.indices.contains(entry.phaseIndex) else { return nil }
                return ObjectVariantAssigner.entryOrientation(entry, crystal: library.phases[entry.phaseIndex].crystal)
            }
            let matrixEntry = library.entries[matrixEntryIndex]
            guard let fitted = orientation(matrixEntry) else { return nil }
            // The matcher returns any one of the in-plane angles the matrix's symmetry about the beam makes equal (four for Al [001]);
            // the variant numbers and the needle directions are counted in the matrix frame, so the frame is made canonical (#155).
            let matrix = ObjectVariantAssigner.canonicalMatrixOrientation(fitted, crystal: library.phases[matrixEntry.phaseIndex].crystal)
            let beamAxis = PhaseReferenceLibrary.cartesianZoneAxis(matrixEntry.zoneAxis, crystal: library.phases[matrixEntry.phaseIndex].crystal)
            let beam = beamAxis
                .flatMap { axis -> Int? in
                    let m = (0..<3).max { abs(axis[$0]) < abs(axis[$1]) } ?? 0
                    return abs(abs(axis[m]) - 1) < 1e-6 ? m : nil
                }
            return Orientations(entryPhase: library.entries.map(\.phaseIndex), entryOrientation: library.entries.map(orientation),
                                matrixOrientation: matrix, inPlaneStepDegrees: library.settings.inPlaneStepDeg, matrixBeamDirection: beam, matrixBeamAxis: beamAxis)
        }
    }

    /// The one orientation that stands for `orientation` and for every orientation the matrix's own symmetry about the beam makes
    /// equivalent to it: the one with the smallest non-negative in-plane angle against the kit's detector basis of that beam. A crystal seen
    /// down a symmetry axis gives the same pattern at each of those angles (Al [001]: 12, 102, 192 and 282 degrees), the matcher's choice among
    /// them is a tie, and the variant index and the needle direction are counted in the matrix frame: without this the same needles were
    /// numbered differently from run to run (mac4DSTEM#155). Only operators that keep the beam are used, so the zone axis the user chose
    /// and the end-on direction keep their names. A crystal without a standard setting is returned unchanged.
    /// INTERIM in the app: the rule belongs beside `OrientationVariantSet` in DiffractoKit; delete at DiffractoKit 0.13.0.
    package static func canonicalMatrixOrientation(_ orientation: simd_double3x3, crystal: CrystalStructure) -> simd_double3x3 {
        guard let symmetry = PhaseModel.orientationSymmetry(of: crystal) else { return orientation }
        let beam = orientation.columns.2
        let basis = ZoneAxisFrame.detectorBasis(zoneAxis: beam)
        // An orientation with this beam is basis * Rz(theta); its first column in the basis is (cos theta, -sin theta, 0).
        func inPlaneAngle(_ o: simd_double3x3) -> Double {
            let x = basis.transpose * o.columns.0
            let angle = atan2(-x.y, x.x)
            return angle < -1e-6 ? angle + 2 * .pi : max(angle, 0)
        }
        var best = orientation, bestAngle = inPlaneAngle(orientation)
        for g in symmetry.operators {
            let candidate = g * orientation
            guard simd_length(candidate.columns.2 - beam) < 1e-6 else { continue }
            let angle = inPlaneAngle(candidate)
            if angle < bestAngle - 1e-6 { best = candidate; bestAngle = angle }
        }
        return best
    }

    /// One frame for every orientation the matrix's symmetry makes equivalent to `orientation`, whatever its beam: of the equivalent
    /// orientations, the one whose beam is largest in (z, then y, then x), and among those the smallest non-negative in-plane angle
    /// (`canonicalMatrixOrientation`). For aluminium seen down a cube axis the beam becomes [0 0 1], as a typed zone axis has it, so the
    /// variant numbers of a found orientation and of a typed one are the same numbers. Positions of one grain get one frame; a grain whose
    /// beam lies on a boundary of that order can flip between two frames from position to position, and its objects then say "tie".
    package static func canonicalMatrixFrame(_ orientation: simd_double3x3, crystal: CrystalStructure) -> simd_double3x3 {
        guard let symmetry = PhaseModel.orientationSymmetry(of: crystal) else { return orientation }
        func key(_ b: SIMD3<Double>) -> SIMD3<Double> { SIMD3((b.z * 1e4).rounded(), (b.y * 1e4).rounded(), (b.x * 1e4).rounded()) }
        var best = orientation, bestKey = key(orientation.columns.2)
        for g in symmetry.operators {
            let candidate = g * orientation
            let k = key(candidate.columns.2)
            if k.x > bestKey.x || (k.x == bestKey.x && (k.y > bestKey.y || (k.y == bestKey.y && k.z > bestKey.z))) { best = candidate; bestKey = k }
        }
        return canonicalMatrixOrientation(best, crystal: crystal)
    }

    /// An entry's orientation: its zone axis in the crystal's Cartesian frame, then its in-plane rotation (the library rotates the projected
    /// vectors by +theta, which is `ZoneAxisFrame.matrix`'s in-plane matrix).
    package static func entryOrientation(_ entry: PhaseOrientationReference, crystal: CrystalStructure) -> simd_double3x3? {
        guard let n = PhaseReferenceLibrary.cartesianZoneAxis(entry.zoneAxis, crystal: crystal) else { return nil }
        return ZoneAxisFrame.matrix(detectorBasis: ZoneAxisFrame.detectorBasis(zoneAxis: n), inPlaneAngle: Float(entry.inPlaneRotationRad))
    }

    /// Assigns each object of `precipitatePhaseIndex`'s class. Objects of other classes are not in the result. `results` is the phase map's
    /// verdict per scan position, row-major; a position votes when it is indexed to an entry of that phase and its nearest variant lies within
    /// the tolerance. The winner is the variant with the most votes (a tie is ambiguous); it is assigned when its share of the object's
    /// pixels reaches the agreement floor.
    package static func run(objects: PrecipitateSegmentation.ClassMapObjects, results: [PhaseVectorResult], orientations: Orientations,
                            precipitatePhaseIndex: Int, setup: VariantSetup, settings: VariantSettings) -> ObjectJoinResult<VariantAssignment> {
        let tolerance = settings.toleranceDegrees ?? orientations.inPlaneStepDegrees / 2
        var nearest: [Int32: (variant: Int, angleDegrees: Double)?] = [:]
        func variant(of entry: Int32) -> (variant: Int, angleDegrees: Double)? {
            if let cached = nearest[entry] { return cached }
            var found: (variant: Int, angleDegrees: Double)?
            if let p = orientations.entryOrientation[Int(entry)],
               let hit = setup.set.nearestVariant(matrixOrientation: orientations.matrixOrientation, precipitateOrientation: p) {
                found = (hit.index, hit.disorientationRad * 180 / .pi)
            }
            nearest[entry] = .some(found)
            return found
        }
        var out = ObjectJoinResult<VariantAssignment>()
        for classObjects in objects.classes where Int(classObjects.label) == precipitatePhaseIndex {
            for object in classObjects.objects {
                var votes = [Int: (count: Int, angleSum: Double)]()
                var groupOf = [Int: [Int]]()   // the group a vote's key stands for (its smallest variant is the key)
                var oriented = 0
                for i in object.pixelIndices where results.indices.contains(i) {
                    let r = results[i]
                    var found: (variant: Int, angleDegrees: Double)?
                    if let precipitates = orientations.positionPrecipitate, let matrices = orientations.positionMatrix {
                        // Orientations found from the structures: this position's own matrix and precipitate orientation.
                        if r.verdict == .indexed, precipitates.indices.contains(i), matrices.indices.contains(i),
                           let p = precipitates[i], let m = matrices[i],
                           let hit = setup.set.nearestVariant(matrixOrientation: m, precipitateOrientation: p) {
                            found = (hit.index, hit.disorientationRad * 180 / .pi)
                        }
                    } else if r.verdict == .indexed, r.entryIndex >= 0, Int(r.entryIndex) < orientations.entryPhase.count,
                              orientations.entryPhase[Int(r.entryIndex)] == precipitatePhaseIndex {
                        found = variant(of: r.entryIndex)
                    }
                    guard let hit = found else { continue }
                    oriented += 1
                    if hit.angleDegrees <= tolerance {
                        // Variants the pattern cannot tell apart at this position are one choice: the vote goes to the group.
                        var key = hit.variant
                        if orientations.positionGrouping.indices.contains(i), orientations.groupings.indices.contains(orientations.positionGrouping[i]),
                           let group = orientations.groupings[orientations.positionGrouping[i]].first(where: { $0.contains(hit.variant) }), let first = group.first {
                            key = first
                            if group.count > 1, groupOf[key] == nil { groupOf[key] = group }
                        }
                        let old = votes[key] ?? (0, 0)
                        votes[key] = (old.count + 1, old.angleSum + hit.angleDegrees)
                    }
                }
                let pixels = max(object.pixelIndices.count, 1)
                guard oriented > 0 else {
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: nil, agreement: 0, status: .noOrientation)
                    out.reasons[object.id] = "no pixel has an orientation"
                    continue
                }
                let top = votes.values.map(\.count).max() ?? 0
                let leaders = votes.filter { $0.value.count == top }.keys.sorted()
                guard top > 0 else {
                    let why = "no pixel is within \(Self.degrees(tolerance)) of a variant"
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: nil, agreement: 0, status: .ambiguous(why))
                    out.reasons[object.id] = why
                    continue
                }
                let winner = leaders[0]
                let agreement = Double(top) / Double(pixels)
                let angle = votes[winner].map { $0.angleSum / Double($0.count) }
                if leaders.count > 1 {
                    let why = "variants \(leaders.map { String($0 + 1) }.joined(separator: " and ")) tie"
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: angle, agreement: agreement, status: .ambiguous(why))
                    out.reasons[object.id] = why
                } else if agreement < settings.agreementMinimum {
                    let why = "only \(Int((agreement * 100).rounded())) % of the pixels agree on variant \(winner + 1)"
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: angle, agreement: agreement, status: .ambiguous(why))
                    out.reasons[object.id] = why
                } else {
                    let others = groupOf[winner].map { $0.filter { $0 != winner }.map { $0 + 1 } }
                    let habit = Self.habit(of: groupOf[winner] ?? [winner], habitFamily: setup.habitFamily, familyNames: setup.familyNames)
                    out.perObject[object.id] = VariantAssignment(variant: winner + 1, direction: habit.direction,
                                                                 directionName: habit.name, angleDegrees: angle,
                                                                 agreement: agreement, status: .assigned,
                                                                 alternatives: (others?.isEmpty ?? true) ? nil : others)
                }
            }
        }
        return out
    }

    /// The habit direction of a group of variants the pattern cannot tell apart (0-based variant indices). When they share one, it is
    /// that direction (the two variants of a needle lying in the foil plane). When they do not (T1 plates on two {111} planes seen down
    /// a cube axis of aluminium), the direction is as undecidable as the variant: no index, and both names ("[11-1] or [111]").
    package static func habit(of group: [Int], habitFamily: [Int], familyNames: [String]) -> (direction: Int?, name: String?) {
        var families: [Int] = []
        for v in group where habitFamily.indices.contains(v) && !families.contains(habitFamily[v]) { families.append(habitFamily[v]) }
        func name(_ f: Int) -> String { familyNames.indices.contains(f) ? familyNames[f] : "[?]" }
        guard let first = families.first else { return (nil, nil) }
        if families.count == 1 { return (first, name(first)) }
        return (nil, families.sorted().map(name).joined(separator: " or "))
    }

    private static func degrees(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX"))) + "\u{00B0}" }
}

/// The variant run on a phase map: which phase, the kit's variant set, the library's orientations, then `ObjectVariantAssigner.run`. A run that
/// cannot be made says why (`unavailable`), never an empty column.
package nonisolated enum ObjectVariantJoin {
    package nonisolated struct Outcome: Sendable, Equatable {
        package var result: ObjectJoinResult<VariantAssignment>
        /// The relationship's matrix direction along the beam (the needles seen end-on, the plates face-on), when there is one.
        package var endOnDirection: Int?
        /// Each variant's habit direction (index into `familyNames`), in the kit's order.
        package var habitFamilies: [Int] = []
        /// The matrix directions those indices name ("[100]"), and the habit.
        package var familyNames: [String] = []
        package var habit: OrientationRelationshipPreset.Habit? = nil
        /// A replayed 5.4 relationship used on a matrix its paper does not state it for, in words (#512).
        package var warning: String? = nil
        /// A map made from the structures: the tolerance used when the user typed none, degrees (the learned relationship's distance to
        /// the named one plus the kit's 3 degrees). nil for typed zone axes, whose default is half the library's in-plane step.
        package var defaultToleranceDegrees: Double? = nil
    }

    /// How far the relationship a structures run learned for a candidate lies from the named one, degrees, up to both symmetries; the
    /// nearest of them when the run learned more than one, 0 when it learned none (such a phase keeps its free-search orientations).
    package static func learnedOffsetDegrees(_ run: StructurePhaseMapping, candidate: Int, named setup: VariantSetup) -> Double {
        guard run.classification.relationships.indices.contains(candidate), run.candidateSymmetries.indices.contains(candidate),
              let relation = setup.set.variants.first else { return 0 }
        let distances = run.classification.relationships[candidate].map {
            PhaseVectorMatcher.relationDistance($0.relation, relation, matrixSymmetry: run.matrixSymmetry,
                                                precipitateSymmetry: run.candidateSymmetries[candidate]) * 180 / .pi
        }
        return distances.min() ?? 0
    }

    /// What a map made from the structures brings to the variant count: the run, and the two structures by the map's phase index.
    package struct StructureRun: Sendable {
        package var run: StructurePhaseMapping
        /// The crystal of each phase of the map, by phase index (the phase list's order).
        package var crystals: [CrystalStructure]
        /// For each phase of the map: its index among the run's candidates, or nil for the matrix.
        package var candidateIndex: [Int?]
        /// How far the run looked (Å⁻¹), the pair radius it matched with, and each phase's excitation slab by phase index: with the
        /// structure they predict a variant's spots, which says which variants the pattern cannot tell apart. Reach 0: not asked.
        package var reachInvAngstrom: Double
        package var pairRadiusInvAngstrom: Double
        package var excitationSlabs: [Double]
        package init(run: StructurePhaseMapping, crystals: [CrystalStructure], candidateIndex: [Int?],
                     reachInvAngstrom: Double = 0, pairRadiusInvAngstrom: Double = 0.02, excitationSlabs: [Double] = []) {
            self.run = run; self.crystals = crystals; self.candidateIndex = candidateIndex
            self.reachInvAngstrom = reachInvAngstrom; self.pairRadiusInvAngstrom = pairRadiusInvAngstrom; self.excitationSlabs = excitationSlabs
        }
    }

    package static func run(objects: PrecipitateSegmentation.ClassMapObjects, map: PhaseMap?, library: PhaseReferenceLibrary?,
                            matrixEntryIndex: Int?, settings: VariantSettings, structureRun: StructureRun? = nil) -> Outcome {
        func unavailable(_ why: String) -> Outcome { Outcome(result: ObjectJoinResult(unavailable: why), endOnDirection: nil, habitFamilies: []) }
        guard settings.source == "known_variants" else { return unavailable("Variants from ACOM orientations are not built yet.") }
        guard let map else { return unavailable("There is no phase map.") }
        guard let relationship = settings.relationship else { return unavailable(VariantError.noRelationship.localizedDescription) }
        let matrixName = map.phaseNames.indices.contains(map.matrixPhaseIndex) ? map.phaseNames[map.matrixPhaseIndex] : "the matrix"
        if let structureRun {
            // Orientations found from the structures (mac4DSTEM#245).
            let candidates = map.phaseNames.indices.filter { $0 != map.matrixPhaseIndex }
            guard let phase = settings.phaseName.flatMap({ name in candidates.first { map.phaseNames[$0] == name } }) ?? candidates.first,
                  structureRun.crystals.indices.contains(phase), structureRun.crystals.indices.contains(map.matrixPhaseIndex),
                  structureRun.candidateIndex.indices.contains(phase), let candidate = structureRun.candidateIndex[phase] else {
                return unavailable("Choose the phase that has the orientation relationship to the matrix.")
            }
            let matrixCrystal = structureRun.crystals[map.matrixPhaseIndex]
            guard var orientations = ObjectVariantAssigner.Orientations.make(structureRun: structureRun.run, candidateIndex: candidate,
                                                                             matrixCrystal: matrixCrystal) else {
                return unavailable(VariantError.noMatrixEntry.localizedDescription)
            }
            let setup: VariantSetup
            do { setup = try VariantSetup(precipitate: structureRun.crystals[phase], matrix: matrixCrystal, relationship: relationship) }
            catch { return unavailable((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            // The run classified every position against the variants of the relationship it LEARNED, which on real data lies a few
            // degrees from the named one (the foil bends, the published relationship is ideal). The named relationship numbers those
            // variants: a position is given the named variant nearest to it when it lies within the learned relationship's own distance
            // to the named one plus the kit's angle within which two variants are one. A tolerance the user typed is used as typed.
            let learnedOffset = Self.learnedOffsetDegrees(structureRun.run, candidate: candidate, named: setup)
            orientations.inPlaneStepDegrees = 2 * (learnedOffset + LearnedOrientationRelationship.defaultVariantMergeAngleRad * 180 / .pi)
            // Which variants the pattern cannot tell apart, per beam direction (the groups do not change with the in-plane angle: every
            // variant's spots turn together). Refuse rather than guess: such a group is shown as a group (DiffractoKit#107).
            if structureRun.reachInvAngstrom > 0, structureRun.excitationSlabs.indices.contains(phase),
               let reflections = try? PhaseOrientationCandidate.reflections(of: structureRun.crystals[phase], kMax: structureRun.reachInvAngstrom),
               let precipitates = orientations.positionPrecipitate, let matrices = orientations.positionMatrix {
                var known: [SIMD3<Int>: Int] = [:]
                var groupings: [[[Int]]] = [], perPosition = [Int](repeating: -1, count: matrices.count)
                for i in matrices.indices where precipitates[i] != nil {
                    guard let m = matrices[i] else { continue }
                    let b = m.columns.2
                    let key = SIMD3(Int((b.x * 100).rounded()), Int((b.y * 100).rounded()), Int((b.z * 100).rounded()))
                    if let g = known[key] { perPosition[i] = g; continue }
                    groupings.append(PhaseVectorMatcher.indistinguishableVariants(
                        setup.set.variants, matrixOrientation: m, reflections: reflections,
                        excitationSlabInvAngstrom: structureRun.excitationSlabs[phase], reachInvAngstrom: structureRun.reachInvAngstrom,
                        toleranceInvAngstrom: structureRun.pairRadiusInvAngstrom))
                    known[key] = groupings.count - 1
                    perPosition[i] = groupings.count - 1
                }
                orientations.groupings = groupings
                orientations.positionGrouping = perPosition
            }
            let result = ObjectVariantAssigner.run(objects: objects, results: map.results, orientations: orientations, precipitatePhaseIndex: phase,
                                                   setup: setup, settings: settings)
            return Outcome(result: result, endOnDirection: orientations.matrixBeamAxis.flatMap { setup.family(alongBeam: $0) },
                           habitFamilies: setup.habitFamily, familyNames: setup.familyNames, habit: relationship.habit,
                           warning: relationship.example?.warning(matrix: matrixCrystal, matrixName: matrixName),
                           defaultToleranceDegrees: orientations.inPlaneStepDegrees / 2)
        }
        guard let library else { return unavailable("The phase map's reference library is not kept; map the phases again.") }
        guard let matrixEntryIndex, matrixEntryIndex >= 0 else { return unavailable(VariantError.noMatrixEntry.localizedDescription) }
        let candidates = map.phaseNames.indices.filter { $0 != map.matrixPhaseIndex }
        guard let phase = settings.phaseName.flatMap({ name in candidates.first { map.phaseNames[$0] == name } }) ?? candidates.first,
              library.phases.indices.contains(phase), library.phases.indices.contains(map.matrixPhaseIndex) else {
            return unavailable("Choose the phase that has the orientation relationship to the matrix.")
        }
        guard let orientations = ObjectVariantAssigner.Orientations.make(library: library, matrixEntryIndex: matrixEntryIndex) else {
            return unavailable(VariantError.noMatrixEntry.localizedDescription)
        }
        let setup: VariantSetup
        let matrixCrystal = library.phases[map.matrixPhaseIndex].crystal
        do { setup = try VariantSetup(precipitate: library.phases[phase].crystal, matrix: matrixCrystal, relationship: relationship) }
        catch { return unavailable((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        let result = ObjectVariantAssigner.run(objects: objects, results: map.results, orientations: orientations, precipitatePhaseIndex: phase,
                                               setup: setup, settings: settings)
        // The cube-axis presets keep the orientation's own cube-axis index (unchanged for beta''); a beam along no cube axis can still be a <111> family.
        let endOn = orientations.matrixBeamAxis.map { setup.family(alongBeam: $0) } ?? orientations.matrixBeamDirection
        return Outcome(result: result, endOnDirection: endOn, habitFamilies: setup.habitFamily, familyNames: setup.familyNames,
                       habit: relationship.habit, warning: relationship.example?.warning(matrix: matrixCrystal, matrixName: matrixName))
    }
}
