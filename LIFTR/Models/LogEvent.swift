//
//  LogEvent.swift
//  LIFTR
//

import Foundation
import SwiftData

/// Something you can log with one tap.
enum Product: String, CaseIterable, Identifiable {
    case cigarette, vape, pouch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cigarette: "Cigarette"
        case .vape: "Vape"
        case .pouch: "Pouch"
        }
    }

    func noun(_ count: Int) -> String {
        switch self {
        case .cigarette: count == 1 ? "cigarette" : "cigarettes"
        case .vape: count == 1 ? "vape" : "vapes"
        case .pouch: count == 1 ? "pouch" : "pouches"
        }
    }
}

/// A single moment: one cigarette, a craving, an answer to a check-in.
///
/// `DailyLog` holds each day's totals; events add the time of day and what set it off,
/// which is what the patterns on Progress and Coach are built from.
@Model
final class LogEvent {
    enum Kind: String {
        case cigarette, vape, pouch
        /// The user opened craving help and used it.
        case craving
        /// The user answered "How are you feeling?". The answer is in `note`.
        case feeling
    }

    var timestamp: Date
    var kindRaw: String
    /// What set it off, like "Stress" or "Coffee".
    var trigger: String?
    var note: String?
    /// "manual", "voice" or "notification".
    var source: String

    init(kind: Kind, timestamp: Date = .now, trigger: String? = nil, note: String? = nil, source: String = "manual") {
        self.kindRaw = kind.rawValue
        self.timestamp = timestamp
        self.trigger = trigger
        self.note = note
        self.source = source
    }

    var kind: Kind? { Kind(rawValue: kindRaw) }

    var product: Product? { Product(rawValue: kindRaw) }
}

extension LogEvent.Kind {
    init(_ product: Product) {
        switch product {
        case .cigarette: self = .cigarette
        case .vape: self = .vape
        case .pouch: self = .pouch
        }
    }

    /// Uses and cravings both show when cravings hit.
    var countsAsCraving: Bool { self != .feeling }
}
