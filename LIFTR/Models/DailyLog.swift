//
//  DailyLog.swift
//  LIFTR
//

import Foundation
import SwiftData

/// One check-in per calendar day. A day with zero cigarettes counts as sober.
@Model
final class DailyLog {
    /// Start of the calendar day this log covers.
    @Attribute(.unique) var day: Date
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
        self.day = Calendar.current.startOfDay(for: day)
        self.cigarettesSmoked = max(0, cigarettesSmoked)
        self.cravingLevel = cravingLevel
        self.mood = mood
        self.note = note
        self.source = source
        self.updatedAt = .now
    }

    var isSober: Bool { cigarettesSmoked == 0 }
}
