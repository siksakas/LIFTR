//
//  CircleModels.swift
//  LIFTR
//

import Foundation
import SwiftData
import SwiftUI

/// Someone cheering the user on. They start as invited; once something they sent is saved,
/// they've joined.
@Model
final class CircleMember {
    var name: String
    var invitedAt: Date
    /// Voice notes or photos the invite asked for, like "voice notes, photos".
    var asksFor: String
    @Relationship(deleteRule: .cascade, inverse: \Encouragement.member)
    var items: [Encouragement] = []

    init(name: String, asksFor: String, invitedAt: Date = .now) {
        self.name = name
        self.asksFor = asksFor
        self.invitedAt = invitedAt
    }

    var hasJoined: Bool { !items.isEmpty }

    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    /// Soft avatar colour, stable for a given name.
    var avatarColor: Color {
        let colors: [UInt32] = [0xE8D6B4, 0xDCE8F4, 0xE4DCF0, 0xE6EDE1, 0xF4EBDA]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: colors[sum % colors.count])
    }

    /// "2 voice notes · 1 photo", or "Waiting for what they send".
    var summary: String {
        let voices = items.filter { $0.kind == .voice }.count
        let photos = items.filter { $0.kind == .photo }.count
        var parts: [String] = []
        if voices > 0 { parts.append("\(voices) voice note\(voices == 1 ? "" : "s")") }
        if photos > 0 { parts.append("\(photos) photo\(photos == 1 ? "" : "s")") }
        return parts.isEmpty ? "Waiting for what they send" : parts.joined(separator: " · ")
    }
}

/// A voice note or photo from someone in the circle, saved to play during craving help.
@Model
final class Encouragement {
    enum Kind: String { case voice, photo }

    var kindRaw: String
    /// File name inside `Encouragement.folder`.
    var fileName: String
    var caption: String?
    /// Length of a voice note, in seconds.
    var duration: Double?
    var createdAt: Date
    var member: CircleMember?

    init(kind: Kind, fileName: String, caption: String? = nil, duration: Double? = nil, member: CircleMember?) {
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.caption = caption
        self.duration = duration
        self.createdAt = .now
        self.member = member
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .voice }

    var fileURL: URL { Self.folder.appending(path: fileName) }

    /// Where saved voice notes and photos live: Application Support, so they're backed up
    /// with the app but don't show up in the Files app.
    static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Circle", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
