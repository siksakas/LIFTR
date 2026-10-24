//
//  VoiceTranscript.swift
//  LIFTR
//

import Foundation
import SwiftData

/// What was said in one voice check-in. Saved on the phone when the call ends,
/// then sent to the backend, which keeps it in Snowflake.
@Model
final class VoiceTranscript {
    /// `nonisolated` so SwiftData can encode it off the main actor.
    nonisolated struct Line: Codable, Equatable {
        var fromUser: Bool
        var text: String
    }

    /// Random ID, so sending the same call again overwrites it in Snowflake.
    @Attribute(.unique) var id: String
    var startedAt: Date
    var endedAt: Date
    var lines: [Line]
    /// What the agent logged during the call, e.g. "Today logged as sober". Nil if nothing was.
    var loggedSummary: String?
    /// When the backend saved it. Nil until then.
    var syncedAt: Date? = nil

    init(startedAt: Date, endedAt: Date = .now, lines: [Line], loggedSummary: String?) {
        self.id = UUID().uuidString
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lines = lines
        self.loggedSummary = loggedSummary
    }
}
