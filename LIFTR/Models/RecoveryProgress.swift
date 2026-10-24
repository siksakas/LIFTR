//
//  RecoveryProgress.swift
//  LIFTR
//

import Foundation

/// Everything the app shows about the user's progress, derived from their daily logs.
///
/// Kept as a pure value computed from plain per-day counts so the rules are
/// easy to read and tweak in one place.
struct RecoveryProgress: Equatable {
    struct Day: Equatable {
        var day: Date
        var cigarettes: Int
        var vapes = 0
        var pouches = 0

        /// Everything with nicotine that day.
        var total: Int { cigarettes + vapes + pouches }
    }

    struct WeekScore: Equatable {
        /// 0 for today, 1 for a week ago, and so on.
        var weeksAgo: Int
        var score: Int
    }

    /// Consecutive nicotine-free days ending today (or yesterday, if today isn't logged yet).
    var currentStreak: Int
    var longestStreak: Int
    var totalSoberDays: Int
    var cigarettesLast7Days: Int
    var loggedToday: Bool
    var cigarettesToday: Int?
    var vapesToday: Int
    var pouchesToday: Int
    /// The first logged day, or nil before anything is logged.
    var firstDay: Date?
    /// How much the user usually has in a day: the average of their first week of logs.
    var baseline: Double
    /// Credit-score style number from 300 to 850.
    var score: Int
    /// The score seven days ago, or nil if there's no history that far back.
    var scoreWeekAgo: Int?
    /// The score at the same weekday for each of the last six weeks, oldest first, ending today.
    var weeklyScores: [WeekScore]
    /// Where Tuk is. Follows the score, but a slip only moves Tuk back one stage at most.
    var stage: TukStage
    /// The furthest stage Tuk has reached.
    var highestStage: TukStage

    static let minScore = 300
    static let maxScore = 850
    /// "Your last 3 months" in the score breakdown.
    static let recentWindowDays = 90
    static let recentWeight = 0.7
    /// The first this many logged days set the baseline.
    static let baselineDays = 7
    /// A score needs this many logged days before it can reach full credit, so one good
    /// first day doesn't jump straight to the top.
    static let fullCreditDays = 14

    init(days: [Day], today: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: today)
        var byDay: [Date: Day] = [:]
        for entry in days {
            let key = calendar.startOfDay(for: entry.day)
            byDay[key] = Day(day: key, cigarettes: entry.cigarettes, vapes: entry.vapes, pouches: entry.pouches)
        }

        let todayEntry = byDay[todayStart]
        cigarettesToday = todayEntry?.cigarettes
        vapesToday = todayEntry?.vapes ?? 0
        pouchesToday = todayEntry?.pouches ?? 0
        loggedToday = todayEntry != nil
        totalSoberDays = byDay.values.filter { $0.total == 0 }.count

        // Today still counts as "in progress" until it's logged, so an unlogged
        // today doesn't break the streak. Any other unlogged day does.
        var streak = 0
        var cursor = loggedToday ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        while let entry = byDay[cursor], entry.total == 0 {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        currentStreak = streak

        var longest = 0
        var run = 0
        var previous: Date?
        for day in byDay.keys.sorted() {
            let isConsecutive = previous.map { calendar.date(byAdding: .day, value: 1, to: $0) == day } ?? false
            if byDay[day]?.total == 0 {
                run = isConsecutive ? run + 1 : 1
            } else {
                run = 0
            }
            longest = max(longest, run)
            previous = day
        }
        longestStreak = max(longest, streak)

        let last7Start = calendar.date(byAdding: .day, value: -6, to: todayStart)!
        cigarettesLast7Days = byDay.values
            .filter { $0.day >= last7Start && $0.day <= todayStart }
            .reduce(0) { $0 + $1.cigarettes }

        let logged = byDay.values.filter { $0.day <= todayStart }.sorted { $0.day < $1.day }
        firstDay = logged.first?.day
        baseline = Self.baseline(for: logged)

        let history = Self.scoreHistory(logged: logged, baseline: baseline, through: todayStart, calendar: calendar)
        score = history[todayStart] ?? Self.minScore
        scoreWeekAgo = calendar.date(byAdding: .day, value: -7, to: todayStart).flatMap { history[$0] }
        weeklyScores = (0..<6).reversed().compactMap { weeksAgo in
            calendar.date(byAdding: .day, value: -7 * weeksAgo, to: todayStart)
                .flatMap { history[$0] }
                .map { WeekScore(weeksAgo: weeksAgo, score: $0) }
        }

        highestStage = history.values.map(TukStage.init(score:)).max() ?? .smoking
        stage = Self.stage(score: score, highestStage: highestStage)
    }

    /// Points this week, or nil in the first week.
    var scoreChangeThisWeek: Int? { scoreWeekAgo.map { score - $0 } }

    /// Points until Tuk reaches the next stage, or nil at the top.
    var pointsToNextStage: Int? { stage.next.map { max($0.scoreRange.lowerBound - score, 0) } }

    /// Days since the first log, counting that day as day 1.
    func dayNumber(today: Date = .now, calendar: Calendar = .current) -> Int {
        guard let firstDay else { return 1 }
        let days = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: today)).day ?? 0
        return max(days, 0) + 1
    }

    // MARK: - Rules

    /// The usual amount per day, from the first week of logs. At least 1, so a first week
    /// with no nicotine still gives every later day something to compare against.
    static func baseline(for logged: [Day]) -> Double {
        let firstWeek = logged.prefix(baselineDays)
        guard !firstWeek.isEmpty else { return 1 }
        let average = Double(firstWeek.reduce(0) { $0 + $1.total }) / Double(firstWeek.count)
        return max(1, average)
    }

    /// How good a single day was, from 0 (the usual amount or more) to 1 (none at all).
    /// Cutting down from 6 to 3 scores 0.5, so every cigarette not smoked counts.
    static func dayScore(total: Int, baseline: Double) -> Double {
        max(0, 1 - Double(total) / baseline)
    }

    /// The score is like a credit score: 70% how the last 3 months went, 30% how every day since
    /// the first went. Unlogged days don't count either way. A slip is one day among many, so it
    /// nudges the score down a little and never wipes it out.
    static func score(recentSum: Double, recentDays: Int, allSum: Double, allDays: Int) -> Int {
        guard allDays > 0 else { return minScore }
        let all = allSum / Double(max(allDays, fullCreditDays))
        let recent = recentDays > 0 ? recentSum / Double(max(recentDays, fullCreditDays)) : all
        let weighted = recentWeight * recent + (1 - recentWeight) * all
        return minScore + Int((Double(maxScore - minScore) * weighted).rounded())
    }

    /// Tuk follows the score, but never drops more than one stage below the best stage reached,
    /// and never goes back to the start once it has left it.
    static func stage(score: Int, highestStage: TukStage) -> TukStage {
        let floor = max(highestStage.previous ?? .smoking, min(highestStage, .cuttingDown))
        return max(TukStage(score: score), floor)
    }

    /// The score at the end of every day from the first log through `today`.
    private static func scoreHistory(logged: [Day], baseline: Double, through today: Date, calendar: Calendar) -> [Date: Int] {
        guard var cursor = logged.first?.day else { return [:] }
        let dayScores = logged.map { dayScore(total: $0.total, baseline: baseline) }
        var history: [Date: Int] = [:]
        var next = 0
        var windowStart = 0
        var allSum = 0.0
        var recentSum = 0.0

        while cursor <= today {
            while next < logged.count, logged[next].day <= cursor {
                allSum += dayScores[next]
                recentSum += dayScores[next]
                next += 1
            }
            let oldest = calendar.date(byAdding: .day, value: -(recentWindowDays - 1), to: cursor)!
            while windowStart < next, logged[windowStart].day < oldest {
                recentSum -= dayScores[windowStart]
                windowStart += 1
            }
            history[cursor] = score(recentSum: recentSum, recentDays: next - windowStart, allSum: allSum, allDays: next)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return history
    }
}
