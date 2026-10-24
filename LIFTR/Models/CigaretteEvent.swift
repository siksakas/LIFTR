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

    init(id: UUID = UUID(), smokedAt: Date, source: String) {
        self.id = id
        self.smokedAt = smokedAt
        self.source = source
    }
}
