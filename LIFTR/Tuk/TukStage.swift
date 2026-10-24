//
//  TukStage.swift
//  LIFTR
//

import SwiftUI

/// Tuk the tortoise mirrors the habit in five stages that follow the LIFTR Score.
/// See `RecoveryProgress.stage` for how a slip moves Tuk back at most one step.
enum TukStage: Int, CaseIterable, Identifiable, Comparable {
    case smoking = 1
    case cuttingDown
    case recovering
    case healthy
    case thriving

    static let name = "Tuk"

    var id: Int { rawValue }

    static func < (lhs: TukStage, rhs: TukStage) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The stage a score alone would put Tuk at.
    init(score: Int) {
        self = Self.allCases.last { score >= $0.scoreRange.lowerBound } ?? .smoking
    }

    var scoreRange: ClosedRange<Int> {
        switch self {
        case .smoking: 300...449
        case .cuttingDown: 450...579
        case .recovering: 580...669
        case .healthy: 670...749
        case .thriving: 750...850
        }
    }

    var next: TukStage? { TukStage(rawValue: rawValue + 1) }
    var previous: TukStage? { TukStage(rawValue: rawValue - 1) }

    var title: String {
        switch self {
        case .smoking: "Smoking"
        case .cuttingDown: "Cutting down"
        case .recovering: "Recovering"
        case .healthy: "Healthy"
        case .thriving: "Thriving"
        }
    }

    /// How Tuk feels, for "Tuk is feeling … today" in the voice agent's greeting.
    var mood: String {
        switch self {
        case .smoking: "a little worn out"
        case .cuttingDown: "sleepy but hopeful"
        case .recovering: "brighter"
        case .healthy: "healthy"
        case .thriving: "wonderful"
        }
    }

    /// One line about this stage, for Tuk's path on the Progress screen.
    var pathLine: String {
        switch self {
        case .smoking: "Tired and hazy. Tuk smokes when you do."
        case .cuttingDown: "Tea instead of a cigarette. The haze is thinning."
        case .recovering: "No smoke at all. Brighter eyes, big stretches."
        case .healthy: "Eyes wide open, a small smile, a first sprout."
        case .thriving: "A little garden on its shell. Happy hops."
        }
    }

    /// What Tuk says on Home when there's nothing more specific to say.
    var homeLine: String {
        switch self {
        case .smoking: "I'm a little worn out. Let's just notice today. No pressure."
        case .cuttingDown: "I'm breathing easier. Slow and steady counts."
        case .recovering: "No smoke around me today. I just had the best stretch."
        case .healthy: "Look, my first sprout. You grew that."
        case .thriving: "My shell is a little garden now. Thanks for sticking with me."
        }
    }

    /// Shell colour, used for the little dot next to the stage name.
    var shellColor: Color {
        switch self {
        case .smoking: Color(hex: 0x9F927E)
        case .cuttingDown: Color(hex: 0xAA977B)
        case .recovering: Color(hex: 0xBD9D70)
        case .healthy: Color(hex: 0xCA9F65)
        case .thriving: Color(hex: 0xDAA95D)
        }
    }

    /// Sky colour of Tuk's little world, shown while the scene loads.
    var skyColor: Color {
        switch self {
        case .smoking: Color(hex: 0xE7E3DA)
        case .cuttingDown: Color(hex: 0xE2E7E4)
        case .recovering: Color(hex: 0xDAE8EF)
        case .healthy: Color(hex: 0xD2E5F3)
        case .thriving: Color(hex: 0xC9E0F5)
        }
    }

    /// Background of the stage preview on Tuk's path.
    var previewColor: Color {
        switch self {
        case .smoking: Color(hex: 0xF1EDE5)
        case .cuttingDown: Color(hex: 0xF3EDE1)
        case .recovering: Color(hex: 0xEEF2EA)
        case .healthy: Color(hex: 0xEAF2E6)
        case .thriving: Color(hex: 0xF2F0DC)
        }
    }

    /// Full-body still, rendered from the rig.
    var image: Image { Image("Tuk\(rawValue)") }
    /// Head-and-shoulders still for avatars.
    var headImage: Image { Image("TukHead\(rawValue)") }
}
