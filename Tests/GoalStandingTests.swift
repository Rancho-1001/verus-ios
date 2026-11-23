import Foundation
import Testing

@testable import Verus

@Suite("Goal standing")
struct GoalStandingTests {

    private let goal = 15_000

    @Test("no reading is unknown, never short")
    func absenceIsNotFailure() {
        // The distinction the whole calendar rests on: a phone left at home
        // is missing data, not a bad day. If this ever returns `.short` the
        // month fills with red for days the user may have walked a marathon.
        #expect(GoalStanding.standing(value: nil as Int?, goal: goal) == .unknown)
        #expect(GoalStanding.standing(value: 0, goal: goal) == .short)
    }

    @Test("the bands fall where the thresholds say")
    func bands() {
        #expect(GoalStanding.standing(value: 7_499, goal: goal) == .short)
        #expect(GoalStanding.standing(value: 7_500, goal: goal) == .closing)   // exactly half
        #expect(GoalStanding.standing(value: 14_999, goal: goal) == .closing)
        #expect(GoalStanding.standing(value: 15_000, goal: goal) == .met)      // exactly the goal
        #expect(GoalStanding.standing(value: 40_000, goal: goal) == .met)
    }

    @Test("a goal of zero cannot be met, divided by, or coloured")
    func zeroGoal() {
        #expect(GoalStanding.standing(value: 9_000, goal: 0) == .unknown)
        #expect(GoalStanding.share(value: 9_000, goal: 0) == 0)
    }

    @Test("the share a progress bar draws is clamped to the track")
    func share() {
        #expect(GoalStanding.share(value: 7_500, goal: goal) == 0.5)
        #expect(GoalStanding.share(value: 0, goal: goal) == 0)
        // Three times the goal is still a full bar: a bar overflowing its
        // track says nothing a full one does not.
        #expect(GoalStanding.share(value: 45_000, goal: goal) == 1)
        #expect(GoalStanding.share(value: nil as Int?, goal: goal) == 0)
    }

    @Test("weight takes its colour from the projection, not from a share")
    func weightStanding() {
        #expect(GoalStanding.standing(for: .reached) == .met)
        #expect(
            GoalStanding.standing(
                for: .onTrack(date: .now, weeks: 6, rateKilogramsPerWeek: -0.3)
            ) == .met
        )
        // Flat is amber, not green. The trend going nowhere is not progress.
        #expect(GoalStanding.standing(for: .tooSlowToProject) == .closing)
        #expect(GoalStanding.standing(for: .movingAway(rateKilogramsPerWeek: 0.2)) == .short)
        // And too little data is grey rather than any verdict at all.
        #expect(GoalStanding.standing(for: .notEnoughData(needed: 9)) == .unknown)
    }

    @Test("miles come from the phone's own distance, not from a stride guess")
    func miles() throws {
        let day = Date(timeIntervalSince1970: 1_764_000_000)
        let withDistance = DailyActivity(
            day: day, steps: 10_000, activeKilocalories: 400,
            restingKilocalories: 1_700, distanceMeters: 8_046.72
        )
        let miles = try #require(withDistance.miles)
        #expect(abs(miles - 5) < 0.000_1)

        // 10,000 steps and no distance reports no distance. Multiplying by an
        // assumed stride would invent a number the phone declined to give.
        let withoutDistance = DailyActivity(
            day: day, steps: 10_000, activeKilocalories: 400, restingKilocalories: 1_700
        )
        #expect(withoutDistance.miles == nil)
    }
}
