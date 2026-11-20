import Foundation
import Testing

@testable import Verus

private func kg(_ pounds: Double) -> Double { pounds / WeightEntry.poundsPerKilogram }
private func lb(_ kilograms: Double) -> Double { kilograms * WeightEntry.poundsPerKilogram }

@Suite("Lean mass")
struct LeanMassTests {

    @Test("lean mass is what is left after the fat")
    func basic() throws {
        // 200 lb at 20% body fat is 160 lb of lean mass.
        let lean = try #require(
            BodyComposition.leanKilograms(weightKilograms: kg(200), bodyFatPercent: 20)
        )
        #expect(abs(lb(lean) - 160) < 0.001)
    }

    @Test("a percentage outside the possible range is rejected, not modelled")
    func rejectsImpossiblePercentages() {
        // Zero per cent is not survivable and a hundred is not a person, so
        // both are data entry errors rather than edge cases.
        #expect(BodyComposition.leanKilograms(weightKilograms: kg(180), bodyFatPercent: 0) == nil)
        #expect(BodyComposition.leanKilograms(weightKilograms: kg(180), bodyFatPercent: 100) == nil)
        #expect(BodyComposition.leanKilograms(weightKilograms: kg(180), bodyFatPercent: -5) == nil)
        #expect(BodyComposition.leanKilograms(weightKilograms: 0, bodyFatPercent: 20) == nil)
    }
}

@Suite("Weight at a body-fat target")
struct WeightForBodyFatTests {

    @Test("holding lean mass, a lower body fat means a lower weight")
    func lowerFatLowerWeight() throws {
        let lean = try #require(
            BodyComposition.leanKilograms(weightKilograms: kg(180), bodyFatPercent: 22)
        )
        let at15 = try #require(BodyComposition.weightForBodyFat(targetPercent: 15, leanKilograms: lean))
        let at10 = try #require(BodyComposition.weightForBodyFat(targetPercent: 10, leanKilograms: lean))
        #expect(lb(at10) < lb(at15))
        #expect(lb(at15) < 180)
    }

    @Test("the round trip holds: weight → fat → weight")
    func inverseAgrees() throws {
        let lean = try #require(
            BodyComposition.leanKilograms(weightKilograms: kg(180), bodyFatPercent: 22)
        )
        let target = try #require(BodyComposition.weightForBodyFat(targetPercent: 12, leanKilograms: lean))
        let backAgain = try #require(
            BodyComposition.bodyFatPercent(atWeightKilograms: target, leanKilograms: lean)
        )
        #expect(abs(backAgain - 12) < 0.000_1)
    }

    @Test("a target of a hundred per cent has no answer rather than infinity")
    func noDivisionByZero() {
        #expect(BodyComposition.weightForBodyFat(targetPercent: 100, leanKilograms: 60) == nil)
    }

    @Test("lean mass heavier than the weight has no body fat answer")
    func impossibleComposition() {
        #expect(
            BodyComposition.bodyFatPercent(atWeightKilograms: kg(150), leanKilograms: kg(160)) == nil
        )
    }
}

@Suite("How the two goals relate")
struct GoalRelationshipTests {

    @Test("with no body fat recorded there is nothing to relate")
    func needsBodyFat() {
        let relationship = BodyComposition.relationship(
            currentWeightKilograms: kg(180),
            currentBodyFatPercent: nil,
            goalWeightKilograms: kg(150),
            goalBodyFatPercent: 10
        )
        #expect(relationship == .noBodyFatRecorded)
    }

    @Test("the concept's own case: 180 lb, aiming at 150 lb and under 10%")
    func theFoundersGoal() throws {
        // At 180 lb and 25% body fat, lean mass is 135 lb. Ten per cent body
        // fat then lands at 135 / 0.9 = 150 lb — the same number as the weight
        // goal. That is the convergence the concept describes, and this test
        // is what keeps the screen able to say so.
        let relationship = BodyComposition.relationship(
            currentWeightKilograms: kg(180),
            currentBodyFatPercent: 25,
            goalWeightKilograms: kg(150),
            goalBodyFatPercent: 10
        )
        guard case .converge(let atPounds) = relationship else {
            Issue.record("expected .converge, got \(relationship)")
            return
        }
        #expect(abs(atPounds - 150) < 0.001)
    }

    @Test("carrying more fat means the body-fat goal is the harder one")
    func bodyFatArrivesLater() throws {
        // 180 lb at 30% is 126 lb lean; 10% body fat needs 140 lb — which is
        // *below* a 150 lb weight goal, so the scale target is crossed first
        // and the body-fat target needs more work after it.
        let relationship = BodyComposition.relationship(
            currentWeightKilograms: kg(180),
            currentBodyFatPercent: 30,
            goalWeightKilograms: kg(150),
            goalBodyFatPercent: 10
        )
        guard case .weightReachedFirst(let atPounds) = relationship else {
            Issue.record("expected .weightReachedFirst, got \(relationship)")
            return
        }
        #expect(atPounds < 150)
        #expect(abs(atPounds - 140) < 0.001)
    }

    @Test("carrying less fat means the body-fat goal arrives on the way down")
    func bodyFatArrivesFirst() throws {
        // 180 lb at 18% is 147.6 lb lean; 10% lands at 164 lb, well above a
        // 150 lb weight goal — so the percentage is reached first and the rest
        // of the journey is weight, not fat.
        let relationship = BodyComposition.relationship(
            currentWeightKilograms: kg(180),
            currentBodyFatPercent: 18,
            goalWeightKilograms: kg(150),
            goalBodyFatPercent: 10
        )
        guard case .bodyFatReachedFirst(let atPounds) = relationship else {
            Issue.record("expected .bodyFatReachedFirst, got \(relationship)")
            return
        }
        #expect(atPounds > 150)
    }

    @Test("within two pounds the two goals are treated as the same goal")
    func toleranceIsHonestAboutPrecision() {
        // Any consumer body-fat reading has more error than this, so splitting
        // hairs below two pounds would be false precision.
        let relationship = BodyComposition.relationship(
            currentWeightKilograms: kg(180),
            currentBodyFatPercent: 25.3,
            goalWeightKilograms: kg(150),
            goalBodyFatPercent: 10
        )
        guard case .converge = relationship else {
            Issue.record("expected .converge for a near miss, got \(relationship)")
            return
        }
    }
}
