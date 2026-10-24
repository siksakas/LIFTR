//
//  TrendSummary.swift
//  LIFTR
//

import Foundation

/// Averages and patterns for the Trends tab, computed from the logs on the phone,
/// so the tab works without the backend.
struct TrendSummary {
    /// One bar segment in the 30-day chart: how many of one nicotine type on one day.
    struct DayUse: Identifiable {
        var day: Date
        var type: String
        var count: Int
        var id: String { "\(day.timeIntervalSince1970)-\(type)" }
    }

    struct TypeTotal: Identifiable {
        var type: String
        var count: Int
        var id: String { type }
    }

    /// Chart legend order. Matches the colors in TrendsView.
    static let types = ["Cigarettes", "Vape", "Pouches", "Other"]

    var chart: [DayUse]
    /// Average uses per logged day. Nil when nothing was logged in that window.
    var averageLast7: Double?
    var averageLast30: Double?
    var averagePrevious30: Double?
    /// Change of the last 30 days against the 30 before, in percent. Negative means cutting down.
    var changePercent: Int?
    var loggedDaysLast30: Int
    var soberDaysLast30: Int
    /// The weekday with the most use on average over the last 30 days.
    var heaviestWeekday: String?
    var averageCravingLast7: Double?
    /// Totals per type over the last 30 days, biggest first, types with no use left out.
    var totalsLast30: [TypeTotal]

    init(logs: [DailyLog], today: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: today)
        let withAge = logs.map { log in
            (log: log, daysAgo: calendar.dateComponents([.day], from: calendar.startOfDay(for: log.day), to: todayStart).day ?? .max)
        }
        let last7 = withAge.filter { (0..<7).contains($0.daysAgo) }.map { $0.log }
        let last30 = withAge.filter { (0..<30).contains($0.daysAgo) }.map { $0.log }
        let previous30 = withAge.filter { (30..<60).contains($0.daysAgo) }.map { $0.log }

        chart = last30.flatMap { log in
            zip(Self.types, Self.counts(log))
                .filter { $0.1 > 0 }
                .map { DayUse(day: log.day, type: $0.0, count: $0.1) }
        }

        let recent = Self.average(last30)
        let earlier = Self.average(previous30)
        averageLast7 = Self.average(last7)
        averageLast30 = recent
        averagePrevious30 = earlier
        if let now = recent, let before = earlier, before > 0 {
            changePercent = Int(((now - before) / before * 100).rounded())
        } else {
            changePercent = nil
        }

        loggedDaysLast30 = last30.count
        soberDaysLast30 = last30.filter(\.isSober).count

        var byWeekday: [String: [Int]] = [:]
        for log in last30 {
            byWeekday[log.day.formatted(.dateTime.weekday(.wide)), default: []].append(log.totalUses)
        }
        heaviestWeekday = byWeekday
            .map { (name: $0.key, average: Double($0.value.reduce(0, +)) / Double($0.value.count)) }
            .filter { $0.average > 0 }
            .max { $0.average < $1.average }?.name

        let cravings = last7.compactMap(\.cravingLevel)
        averageCravingLast7 = cravings.isEmpty ? nil : Double(cravings.reduce(0, +)) / Double(cravings.count)

        totalsLast30 = Self.types.indices
            .map { index in TypeTotal(type: Self.types[index], count: last30.reduce(0) { $0 + Self.counts($1)[index] }) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    /// Counts in the same order as `types`.
    private static func counts(_ log: DailyLog) -> [Int] {
        [log.cigarettesSmoked, log.vapeSessions, log.pouches, log.otherUses]
    }

    private static func average(_ logs: [DailyLog]) -> Double? {
        logs.isEmpty ? nil : Double(logs.reduce(0) { $0 + $1.totalUses }) / Double(logs.count)
    }
}
