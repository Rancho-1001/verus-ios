import Foundation

/// Where a number stands against the goal it is aimed at.
///
/// The app used to say this with one colour at varying strength: a pale
/// accent wash for a quiet day, a strong one for a good day. That reads as a
/// single smooth ramp, which is honest but slow — telling a 6,000-step day
/// from a 12,000-step day meant comparing two shades of the same green.
///
/// Three named bands say it in one glance instead: short, closing, met. The
/// bands are the only place the thresholds live, so the month calendar, the
/// year grid and the Home tiles cannot drift apart from each other.
///
/// There is deliberately no "nearly" band above the goal. Past the goal the
/// day is met, and 40,000 steps is not a different verdict from 15,000 — it
/// is the same verdict with a bigger number next to it.
enum GoalStanding: Hashable, Sendable, CaseIterable {
    /// No reading at all. Not zero — absence. The calendar draws these blank
    /// rather than red, because a phone left at home is not a bad day.
    case unknown
    /// Under half the goal.
    case short
    /// Half the goal or more, but not there yet.
    case closing
    /// At the goal or past it.
    case met

    /// Where `closing` begins, as a share of the goal. Half is a judgement
    /// call and the only one in this file: it is the point at which the day
    /// is recoverable by an evening walk rather than by a different day.
    static let closingThreshold = 0.5

    static func standing(value: Double?, goal: Double) -> GoalStanding {
        guard let value, goal > 0 else { return .unknown }
        let share = value / goal
        if share >= 1 { return .met }
        return share >= closingThreshold ? .closing : .short
    }

    static func standing(value: Int?, goal: Int) -> GoalStanding {
        standing(value: value.map(Double.init), goal: Double(goal))
    }

    /// How far along the goal a value is, clamped to 0...1 — what a progress
    /// bar draws. Capped because a bar that overflows its track says nothing
    /// a bar that is full does not already say.
    static func share(value: Double?, goal: Double) -> Double {
        guard let value, goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }

    static func share(value: Int?, goal: Int) -> Double {
        share(value: value.map(Double.init), goal: Double(goal))
    }

    /// Weight gets its standing from the direction of travel, not from a
    /// share of a daily target.
    ///
    /// A weight goal is not something you meet half of today — you are either
    /// moving toward it, holding still, or moving away. So the three bands map
    /// onto the projection the trend engine already computes, which means the
    /// colour on the Home tile and the sentence on the Weight screen cannot
    /// disagree: both read the same case.
    static func standing(for projection: TrendEngine.Projection) -> GoalStanding {
        switch projection {
        case .reached, .onTrack: .met
        case .tooSlowToProject: .closing
        case .movingAway: .short
        case .notEnoughData: .unknown
        }
    }
}
