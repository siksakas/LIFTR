//
//  RecoveryProgress.swift
//  LIFTR
//

import Foundation

/// Everything the app shows about the user's progress, derived from their daily logs.
///
/// Kept as a pure value computed from plain `(day, cigarettes)` pairs so the rules are
/// easy to read and tweak in one place.
struct RecoveryProgress: Equatable {
    struct Day: Equatable {
        var day: Date
        /// Every nicotine use that day (cigarettes, vape sessions, pouches, other), not only cigarettes.
        /// The name stays because the voice agent's prompt and tools use "cigarettes".
        var cigarettes: Int
    }

    /// Consecutive sober days ending today (or yesterday, if today isn't logged yet).
    var currentStreak: Int
    var longestStreak: Int
    var totalSoberDays: Int
    var cigarettesLast7Days: Int
    var loggedToday: Bool
    var cigarettesToday: Int?
    /// Credit-score style number from 300 to 850.
    var score: Int
    /// Pet health from 0 to 100.
    var petHealth: Int

    static let minScore = 300
    static let maxScore = 850

    init(days: [Day], today: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: today)
        var byDay: [Date: Int] = [:]
        for entry in days {
            byDay[calendar.startOfDay(for: entry.day)] = entry.cigarettes
        }

        cigarettesToday = byDay[todayStart]
        loggedToday = cigarettesToday != nil
        totalSoberDays = byDay.values.filter { $0 == 0 }.count

        // Today still counts as "in progress" until it's logged, so an unlogged
        // today doesn't break the streak. Any other unlogged day does.
        var streak = 0
        var cursor = loggedToday ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        while let cigarettes = byDay[cursor], cigarettes == 0 {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        currentStreak = streak

        var longest = 0
        var run = 0
        var previous: Date?
        for day in byDay.keys.sorted() {
            let isConsecutive = previous.map { calendar.date(byAdding: .day, value: 1, to: $0) == day } ?? false
            if byDay[day] == 0 {
                run = isConsecutive ? run + 1 : 1
            } else {
                run = 0
            }
            longest = max(longest, run)
            previous = day
        }
        longestStreak = max(longest, streak)

        let last7Start = calendar.date(byAdding: .day, value: -6, to: todayStart)!
        cigarettesLast7Days = byDay
            .filter { $0.key >= last7Start && $0.key <= todayStart }
            .reduce(0) { $0 + $1.value }

        let last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart)!
        let last30 = byDay.filter { $0.key >= last30Start && $0.key <= todayStart }
        let sober30 = last30.values.filter { $0 == 0 }.count

        score = Self.score(streak: streak, loggedDays30: last30.count, soberDays30: sober30)
        petHealth = Self.petHealth(streak: streak, cigarettesLast7Days: cigarettesLast7Days)
    }

    /// Score rewards three things, like a credit score rewards history:
    /// - 50%: the current streak, maxing out at 90 days
    /// - 30%: share of logged days in the last 30 that were sober
    /// - 20%: checking in consistently (days logged out of the last 30)
    static func score(streak: Int, loggedDays30: Int, soberDays30: Int) -> Int {
        let streakFactor = min(Double(streak), 90) / 90
        let soberRate = loggedDays30 == 0 ? 0 : Double(soberDays30) / Double(loggedDays30)
        let consistency = min(Double(loggedDays30), 30) / 30
        let weighted = 0.5 * streakFactor + 0.3 * soberRate + 0.2 * consistency
        return minScore + Int((Double(maxScore - minScore) * weighted).rounded())
    }

    /// The pet starts at 50, gains 5 per sober day in the streak (up to +50),
    /// and loses 2 per cigarette smoked in the last week (up to -50).
    static func petHealth(streak: Int, cigarettesLast7Days: Int) -> Int {
        let health = 50 + min(streak * 5, 50) - min(cigarettesLast7Days * 2, 50)
        return min(max(health, 0), 100)
    }

    var petMood: PetMood { PetMood(health: petHealth) }
}

enum PetMood: String {
    case sick, tired, okay, happy, thriving

    init(health: Int) {
        switch health {
        case ..<20: self = .sick
        case ..<40: self = .tired
        case ..<60: self = .okay
        case ..<85: self = .happy
        default: self = .thriving
        }
    }

    var emoji: String {
        switch self {
        case .sick: "🤒"
        case .tired: "😮‍💨"
        case .okay: "🙂"
        case .happy: "😊"
        case .thriving: "🌟"
        }
    }
}

enum Pet {
    static let name = "Sprout"
}
