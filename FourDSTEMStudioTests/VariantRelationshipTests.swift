import XCTest
import simd
import DiffractoCore
import DiffractoOrientation
@testable import FourDSTEMStudio
import DSTEMCore
import DSTEMSession

/// #512: the variant count takes any matrix and a relationship typed as a paper states it (two parallel pairs, orix
/// `Misorientation.from_align_vectors`; the kit keeps the first exact), with the habit and its axis. Nothing is chosen until the person
/// types one, and no built-in relationship is offered. The three Al relationships of 5.4 (β″ Andersen 1998, θ′ and T1 Thronsen 2024)
/// stay only so old sessions and recipes replay with today's numbers (`ObjectVariantsTests`, `DemoV3VariantsTests`); a replayed one
/// warns on another matrix.
final class VariantRelationshipTests: XCTestCase {
    /// Mutation: `VariantSettings()` keeps β″ as its relationship, or the run guesses one - red.
    func testANewCountHasNoRelationshipAndTheRunSaysWhatIsMissing() throws {
        let settings = VariantSettings()
        XCTAssertNil(settings.relationship)
        XCTAssertEqual(settings.parameters["variant_or"], "none")
        XCTAssertEqual(VariantSettings(parameters: settings.parameters), settings, "none replays as none")

        let objects = try PrecipitateSegmentation.classObjects(labels: [0, 0, 1, 0], width: 2, height: 2,
                                                               roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: []),
                                                               pixelSize: nil, pixelUnit: nil)
        let map = PhaseMap(width: 2, height: 2, matrixEntryIndex: 0, phaseNames: ["Fe", "Mg"], matrixPhaseIndex: 0)
        let outcome = ObjectVariantJoin.run(objects: objects, map: map, library: nil, matrixEntryIndex: 0, settings: settings)
        XCTAssertEqual(outcome.result.unavailable, VariantError.noRelationship.localizedDescription)
        XCTAssertTrue(outcome.result.perObject.isEmpty)
    }

    /// The Burgers relationship of hcp Mg in bcc Fe, typed: (0001) ∥ (110), [2-1-10] ∥ [1-11] (three-index [1 0 0] of the hexagonal
    /// cell), plates on the basal plane. Twelve variants (|432| / |O ∩ R 622 R⁻¹| = 24 / 2), their plate normals the six {110} of iron,
    /// two variants each, named as iron's lattice directions. Mutation: the families taken from an Al example (the cube axes), or the
    /// names read from the Cartesian frame of another lattice - red.
    func testATypedRelationshipOnAnotherMatrixNamesItsOwnFamilies() throws {
        let relationship = VariantRelationship(pairs: "(0 0 1) ∥ (1 1 0), [1 0 0] ∥ [1 -1 1]", habit: .plate, habitAxis: SIMD3(0, 0, 1))
        XCTAssertNil(relationship.example)
        let setup = try VariantSetup(precipitate: CrystalPresets.magnesium, matrix: CrystalPresets.iron, relationship: relationship)
        XCTAssertEqual(setup.set.variants.count, 12)
        XCTAssertEqual(setup.familyNames.count, 6, setup.familyNames.joined(separator: " "))
        XCTAssertEqual(Set(setup.familyNames), ["[110]", "[1-10]", "[101]", "[10-1]", "[011]", "[01-1]"])
        XCTAssertEqual(setup.familyNames[VariantSetup.family(nearest: setup.set.matrix * SIMD3(0, 0, 1), in: setup.habitFamilies)], "[110]",
                       "the typed relationship itself puts the basal plane's normal along (110)")
        for f in setup.familyNames.indices { XCTAssertEqual(setup.habitFamily.filter { $0 == f }.count, 2, setup.familyNames[f]) }
        XCTAssertEqual(setup.family(alongBeam: SIMD3(1, 1, 0)).map { setup.familyNames[$0] }, "[110]", "Fe [110] along the beam: those plates lie face-on")
        XCTAssertNil(setup.family(alongBeam: SIMD3(0, 0, 1)))

        var settings = VariantSettings()
        settings.relationship = relationship
        XCTAssertEqual(settings.parameters["variant_or"], "typed")
        XCTAssertEqual(VariantSettings(parameters: settings.parameters), settings, "a typed relationship replays as typed")
        XCTAssertTrue(PrecipitateObjectReport.variantSummary(settings).hasPrefix("(0 0 1) ∥ (1 1 0), [1 0 0] ∥ [1 -1 1]; plate along [0 0 1]"))
        XCTAssertNil(OrientationRelationshipPreset.betaDoublePrimeInAl.warning(matrix: CrystalPresets.aluminum, matrixName: "Al"))
    }

    /// Typed pairs that do not read, or do not fix an orientation, are refused in words.
    func testPairsThatDoNotFixAnOrientationAreRefused() {
        let unreadable = VariantRelationship(pairs: "(0 0 1) ∥ (1 1 0)", habit: .plate, habitAxis: SIMD3(0, 0, 1))
        XCTAssertThrowsError(try VariantSetup(precipitate: CrystalPresets.magnesium, matrix: CrystalPresets.iron, relationship: unreadable)) {
            XCTAssertEqual($0 as? VariantError, .pairsDoNotRead("(0 0 1) ∥ (1 1 0)"))
        }
        let parallel = VariantRelationship(pairs: "[0 0 1] ∥ [1 1 0], [0 0 2] ∥ [1 -1 1]", habit: .plate, habitAxis: SIMD3(0, 0, 1))
        XCTAssertThrowsError(try VariantSetup(precipitate: CrystalPresets.magnesium, matrix: CrystalPresets.iron, relationship: parallel)) {
            XCTAssertEqual($0 as? VariantError, .pairsDoNotFixAnOrientation)
        }
    }

    /// An example on a matrix its paper does not state it for warns, in the block and the door; on Al it does not. Old sessions'
    /// three values replay as the examples.
    func testAnExampleOnAnotherMatrixWarnsAndOldSessionsReplay() throws {
        let warning = try XCTUnwrap(OrientationRelationshipPreset.betaDoublePrimeInAl.warning(matrix: CrystalPresets.copper, matrixName: "Cu"))
        XCTAssertTrue(warning.hasPrefix("Andersen et al., Acta Mater. 46 (1998) 3283 state this relationship for β″ in Al; the matrix here is Cu."), warning)
        for example in OrientationRelationshipPreset.allCases {
            let replayed = try XCTUnwrap(VariantSettings(parameters: ["variant_source": "known_variants", "variant_or": example.rawValue,
                                                                      "variant_agreement_min": "0.5"]))
            XCTAssertEqual(replayed.relationship, VariantRelationship(example: example))
            XCTAssertEqual(replayed.relationship?.title, example.title)
            XCTAssertNotNil(PhaseMappingSlot.parseOrientationRelationships(example.pairsText).flatMap { $0.count == 2 ? $0 : nil },
                            "\(example.pairsText) reads back as two pairs")
        }
        XCTAssertEqual(OrientationRelationshipPreset.betaDoublePrimeInAl.pairsText, "[1 0 0] ∥ [3 2 0], [0 1 0] ∥ [0 0 1]")
    }

    /// The door: typed pairs with the habit and axis, "none", and an old recipe's case name; missing pieces are refused. No tool
    /// offers the old relationships. Mutation: set_precipitates takes variant_example again - red.
    @MainActor
    func testTheDoorTakesTypedPairsNoneAndAnOldRecipe() throws {
        typealias Door = Mac4DSTEMAgentDoor
        let tool = try XCTUnwrap(Door.precipitateTools.first { $0.name == "set_precipitates" })
        XCTAssertFalse(tool.parameters.contains { $0.name == "variant_example" }, "no built-in relationship is offered")
        guard case .success(let old) = Door.variantRelationship(["orientation_relationship": "thetaPrimeInAl"], current: nil) else { return XCTFail() }
        XCTAssertEqual(old?.example, .thetaPrimeInAl, "an old recipe's case name replays")
        guard case .success(let typed) = Door.variantRelationship(["orientation_relationship": "(0 0 1) ∥ (1 1 0), [1 0 0] ∥ [1 -1 1]",
                                                                    "variant_habit": "plate", "variant_habit_axis": "[0 0 1]"], current: nil)
        else { return XCTFail() }
        XCTAssertEqual(typed, VariantRelationship(pairs: "(0 0 1) ∥ (1 1 0), [1 0 0] ∥ [1 -1 1]", habit: .plate, habitAxis: SIMD3(0, 0, 1)))
        guard case .success(let none) = Door.variantRelationship(["orientation_relationship": "none"], current: typed) else { return XCTFail() }
        XCTAssertNil(none)
        guard case .failure(let noAxis) = Door.variantRelationship(["orientation_relationship": "(0 0 1) ∥ (1 1 0), [1 0 0] ∥ [1 -1 1]",
                                                                     "variant_habit": "plate"], current: nil) else { return XCTFail() }
        XCTAssertTrue(noAxis.message.contains("variant_habit_axis"), noAxis.message)
        guard case .failure(let one) = Door.variantRelationship(["orientation_relationship": "(0 0 1) ∥ (1 1 0)"], current: typed)
        else { return XCTFail() }
        XCTAssertTrue(one.message.contains("is not two parallel pairs"), one.message)
        guard case .success(let kept) = Door.variantRelationship(["agreement_min": "0.6"], current: typed) else { return XCTFail() }
        XCTAssertEqual(kept, typed, "nothing about the relationship given: it stays")
    }
}
