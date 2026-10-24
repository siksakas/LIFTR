//
//  UsagePatterns.swift
//  LIFTR
//

import Foundation

/// When cravings tend to hit and what sets them off, from the one-tap logs.
/// Like `RecoveryProgress`, a pure value so the rules stay in one place.
struct UsagePatterns: Equatable {
    /// Parts of the day, matching the bars on the Progress screen.
    enum Window: Int, CaseIterable, Identifiable {
        case earlyMorning, morning, midday, afternoon, lateAfternoon, evening, night

        var id: Int { rawValue }

        init(hour: Int) {
            switch hour {
            case 6..<9: self = .earlyMorning
            case 9..<12: self = .morning
            case 12..<14: self = .midday
            case 14..<16: self = .afternoon
            case 16..<18: self = .lateAfternoon
            case 18..<21: self = .evening
            default: self = .night
            }
        }

        var startHour: Int {
            switch self {
            case .earlyMorning: 6
            case .morning: 9
            case .midday: 12
            case .afternoon: 14
            case .lateAfternoon: 16
            case .evening: 18
            case .night: 21
            }
        }

        /// Label under a bar.
        var shortLabel: String {
            switch self {
            case .earlyMorning: "6–9a"
            case .morning: "9–12"
            case .midday: "12–2"
            case .afternoon: "2–4p"
            case .lateAfternoon: "4–6"
            case .evening: "6–9"
            case .night: "9p+"
            }
        }

        /// "2–4 pm", for headlines.
        var label: String {
            switch self {
            case .earlyMorning: "6–9 am"
            case .morning: "9 am–12 pm"
            case .midday: "12–2 pm"
            case .afternoon: "2–4 pm"
            case .lateAfternoon: "4–6 pm"
            case .evening: "6–9 pm"
            case .night: "After 9 pm"
            }
        }

        /// "Mornings" in "Mornings · coffee".
        var chipLabel: String {
            switch self {
            case .earlyMorning: "Mornings"
            case .night: "Late nights"
            default: label
            }
        }

        /// "Afternoons" in "Afternoons are usually tough."
        var plural: String {
            switch self {
            case .earlyMorning: "Mornings"
            case .morning: "Late mornings"
            case .midday: "Lunchtimes"
            case .afternoon: "Afternoons"
            case .lateAfternoon: "Late afternoons"
            case .evening: "Evenings"
            case .night: "Late nights"
            }
        }

        /// "Afternoon breather"
        var breatherName: String {
            switch startHour {
            case ..<12: "Morning breather"
            case ..<17: "Afternoon breather"
            default: "Evening breather"
            }
        }

        /// Tuk checks in five minutes before the window starts.
        var breatherTime: DateComponents {
            DateComponents(hour: (startHour + 23) % 24, minute: 55)
        }
    }

    struct Event: Equatable {
        var timestamp: Date
        var kind: LogEvent.Kind
        var trigger: String?
    }

    /// Uses and cravings per window over the last 30 days.
    var last30Days: [Window: Int]
    /// The most common trigger per window over the last 30 days.
    var topTriggers: [Window: String]
    /// Uses and cravings per window over the last 7 days.
    var last7Days: [Window: Int]
    var totalLast7Days: Int
    /// Share of this week's logs that fell on Monday to Friday.
    var weekdayShareLast7Days: Double
    /// How many cigarettes the user usually has logged by this time of day, or nil without
    /// enough history.
    var usualCigarettesByNow: Double?

    /// Below this many logs a week, there's no pattern worth pointing out.
    static let minimumForInsight = 4

    init(events: [Event], now: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: now)
        let start30 = calendar.date(byAdding: .day, value: -29, to: todayStart)!
        let start7 = calendar.date(byAdding: .day, value: -6, to: todayStart)!
        let cravings = events.filter { $0.kind.countsAsCraving && $0.timestamp <= now }

        func window(_ event: Event) -> Window { Window(hour: calendar.component(.hour, from: event.timestamp)) }

        let month = cravings.filter { $0.timestamp >= start30 }
        last30Days = Dictionary(grouping: month, by: window).mapValues(\.count)

        var triggers: [Window: String] = [:]
        for (slot, slotEvents) in Dictionary(grouping: month, by: window) {
            let counts = Dictionary(grouping: slotEvents.compactMap(\.trigger), by: { $0 }).mapValues(\.count)
            // Most common, then alphabetical so ties don't flicker between launches.
            if let top = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) {
                triggers[slot] = top.key
            }
        }
        topTriggers = triggers

        let week = cravings.filter { $0.timestamp >= start7 }
        last7Days = Dictionary(grouping: week, by: window).mapValues(\.count)
        totalLast7Days = week.count
        let weekdays = week.filter { !calendar.isDateInWeekend($0.timestamp) }.count
        weekdayShareLast7Days = week.isEmpty ? 0 : Double(weekdays) / Double(week.count)

        // Average over the previous two weeks' days that had any cigarettes logged with a tap.
        let secondsIntoDay = now.timeIntervalSince(todayStart)
        let start14 = calendar.date(byAdding: .day, value: -14, to: todayStart)!
        let pastCigarettes = events.filter { $0.kind == .cigarette && $0.timestamp >= start14 && $0.timestamp < todayStart }
        let byDay = Dictionary(grouping: pastCigarettes) { calendar.startOfDay(for: $0.timestamp) }
        if byDay.count >= 3 {
            let byNow = byDay.map { day, dayEvents in
                dayEvents.filter { $0.timestamp.timeIntervalSince(day) <= secondsIntoDay }.count
            }
            usualCigarettesByNow = Double(byNow.reduce(0, +)) / Double(byDay.count)
        } else {
            usualCigarettesByNow = nil
        }
    }

    /// The window with the most logs in the last 30 days.
    var toughestWindow: Window? { Self.top(last30Days) }

    /// The runner-up, shown as a second chip.
    var secondWindow: Window? {
        guard let first = toughestWindow else { return nil }
        return Self.top(last30Days.filter { $0.key != first })
    }

    /// The window with the most logs this week, once there are enough to mean something.
    var toughestWindowThisWeek: Window? {
        totalLast7Days >= Self.minimumForInsight ? Self.top(last7Days) : nil
    }

    /// "mostly workdays", "mostly weekends", or nil when it's mixed.
    var weekPattern: String? {
        guard totalLast7Days >= Self.minimumForInsight else { return nil }
        if weekdayShareLast7Days >= 0.8 { return "mostly workdays" }
        if weekdayShareLast7Days <= 0.4 { return "mostly weekends" }
        return nil
    }

    private static func top(_ counts: [Window: Int]) -> Window? {
        counts.filter { $0.value > 0 }
            .max { $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value }?
            .key
    }
}
