//
//  DailyLog.swift
//  LIFTR
//

import Foundation
import SwiftData

/// One check-in per calendar day. A day with no nicotine of any kind counts as sober.
@Model
final class DailyLog {
    /// Calendar day this log covers, as "yyyy-MM-dd" in the user's calendar when it was logged.
    /// A string rather than a midnight timestamp so the same day still matches after a timezone change.
    @Attribute(.unique) var dayKey: String
    var cigarettesSmoked: Int
    /// Other nicotine, counted the way people usually count it. 0 when not used.
    var vapeSessions: Int = 0
    var pouches: Int = 0
    /// Cigars, gum, or anything else, one per use.
    var otherUses: Int = 0
    /// How strong cravings were, 0 (none) to 10 (overwhelming). Optional.
    var cravingLevel: Int?
    var mood: String?
    var note: String?
    /// "voice" when the ElevenLabs partner logged it, "manual" otherwise.
    var source: String
    var updatedAt: Date
    /// The `updatedAt` of the version last saved to the backend. Nil until it's synced;
    /// different from `updatedAt` once the log changes again.
    var syncedVersion: Date? = nil

    init(
        day: Date,
        cigarettesSmoked: Int,
        vapeSessions: Int = 0,
        pouches: Int = 0,
        otherUses: Int = 0,
        cravingLevel: Int? = nil,
        mood: String? = nil,
        note: String? = nil,
        source: String = "manual"
    ) {
        self.dayKey = Self.key(for: day)
        self.cigarettesSmoked = max(0, cigarettesSmoked)
        self.vapeSessions = max(0, vapeSessions)
        self.pouches = max(0, pouches)
        self.otherUses = max(0, otherUses)
        self.cravingLevel = cravingLevel
        self.mood = mood
        self.note = note
        self.source = source
        self.updatedAt = .now
    }

    /// Every nicotine use that day, all types added up.
    var totalUses: Int { cigarettesSmoked + vapeSessions + pouches + otherUses }

    var isSober: Bool { totalUses == 0 }

    /// For example "2 cigarettes, 1 vape session", or "Sober".
    var summary: String {
        let parts = [
            Self.count(cigarettesSmoked, "cigarette"),
            Self.count(vapeSessions, "vape session"),
            Self.count(pouches, "pouch", plural: "pouches"),
            Self.count(otherUses, "other use"),
        ].compactMap { $0 }
        return parts.isEmpty ? "Sober" : parts.joined(separator: ", ")
    }

    private static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String? {
        guard n > 0 else { return nil }
        return "\(n) \(n == 1 ? singular : plural ?? singular + "s")"
    }

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
