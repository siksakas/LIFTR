//
//  DailyLog.swift
//  LIFTR
//

import Foundation
import SwiftData

/// One check-in per calendar day. A day with zero cigarettes counts as sober.
@Model
final class DailyLog {
    /// Calendar day this log covers, as "yyyy-MM-dd" in the user's calendar when it was logged.
    /// A string rather than a midnight timestamp so the same day still matches after a timezone change.
    @Attribute(.unique) var dayKey: String
    var cigarettesSmoked: Int
    /// How strong cravings were, 0 (none) to 10 (overwhelming). Optional.
    var cravingLevel: Int?
    var mood: String?
    var note: String?
    /// "voice" when the ElevenLabs partner logged it, "manual" otherwise.
    var source: String
    var updatedAt: Date

    init(
        day: Date,
        cigarettesSmoked: Int,
        cravingLevel: Int? = nil,
        mood: String? = nil,
        note: String? = nil,
        source: String = "manual"
    ) {
        self.dayKey = Self.key(for: day)
        self.cigarettesSmoked = max(0, cigarettesSmoked)
        self.cravingLevel = cravingLevel
        self.mood = mood
        self.note = note
        self.source = source
        self.updatedAt = .now
    }

    var isSober: Bool { cigarettesSmoked == 0 }

    /// Start of `dayKey` in the current calendar.
    var day: Date { Self.date(forKey: dayKey) ?? updatedAt }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(forKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
