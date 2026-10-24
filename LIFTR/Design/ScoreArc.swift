//
//  ScoreArc.swift
//  LIFTR
//

import SwiftUI

/// The top half of a circle, left to right, filling the width of its frame. The frame should be
/// twice as wide as it is tall. Use `.trim` to draw part of it.
struct SemiArc: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        let steps = 120
        for step in 0...steps {
            let point = Self.point(at: Double(step) / Double(steps), center: center, radius: radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Where `fraction` (0 is the left end, 1 the right) falls on the arc.
    static func point(at fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double.pi * (1 - fraction)
        return CGPoint(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
    }
}

extension RecoveryProgress {
    /// Where the score sits between 300 and 850, from 0 to 1.
    static func fraction(of score: Int) -> Double {
        Double(score - minScore) / Double(maxScore - minScore)
    }
}

/// The little score gauge on the Home score card.
struct MiniScoreGauge: View {
    var score: Int

    var body: some View {
        ZStack {
            SemiArc().stroke(Color(hex: 0xE7DECD), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            SemiArc()
                .trim(from: 0, to: RecoveryProgress.fraction(of: score))
                .stroke(Palette.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .frame(width: 42, height: 21)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}
