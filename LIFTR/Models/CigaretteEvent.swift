//
//  CigaretteEvent.swift
//  LIFTR
//

import Foundation
import SwiftData

/// A single cigarette logged the moment it happened, e.g. with one tap on the watch.
///
/// Each one also counts toward that day's `DailyLog`. Keeping the exact time lets the voice
/// partner bring them up at the next check-in ("I saw you had one around 3pm, what was going on?").
@Model
final class CigaretteEvent {
    /// Created on the device that logged it, so a repeated delivery isn't counted twice.
    @Attribute(.unique) var id: UUID
    var smokedAt: Date
    /// "watch" for now; leaves room for other quick-log sources.
    var source: String
    /// False when it arrived after a check-in whose total already included it.
    var countedInDay: Bool
    /// Set once the voice partner has been told about it, so each one is brought up once,
    /// even if it reached the phone after a call had already started.
    var talkedAbout: Bool

    init(id: UUID = UUID(), smokedAt: Date, source: String, countedInDay: Bool = true) {
        self.id = id
        self.smokedAt = smokedAt
        self.source = source
        self.countedInDay = countedInDay
        self.talkedAbout = false
    }
}
