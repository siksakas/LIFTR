//
//  Theme.swift
//  LIFTR
//
//  Colours, type and small shared pieces from the LIFTR design.
//

import SwiftUI

extension Color {
    /// `Color(hex: 0x3F6046)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The design's palette. Light only: the app sets `.preferredColorScheme(.light)`.
enum Palette {
    static let background = Color(hex: 0xFBF8F1)
    static let card = Color(hex: 0xFFFEFB)
    static let cardBorder = Color(hex: 0xE8E0D1)
    static let divider = Color(hex: 0xEFE8DB)
    static let dashed = Color(hex: 0xDCD2C1)
    static let chipBorder = Color(hex: 0xD9CFBE)

    static let ink = Color(hex: 0x2B2621)
    static let inkSecondary = Color(hex: 0x5F574E)
    static let outline = Color(hex: 0x3A302A)
    static let tukInk = Color(hex: 0x3A2E26)

    static let green = Color(hex: 0x3F6046)
    static let greenDark = Color(hex: 0x2F4A35)
    static let greenSoft = Color(hex: 0xE6EDE1)
    static let greenBubble = Color(hex: 0xE3EBDD)
    static let greenInk = Color(hex: 0x22301F)
    static let greenMuted = Color(hex: 0x3F5A43)
    static let greenPulse = Color(hex: 0x8DAA86)
    static let onGreen = Color(hex: 0xFFFDF8)

    static let sky = Color(hex: 0xDCE8F4)
    static let skyBorder = Color(hex: 0xB9CFE6)
    static let skyInk = Color(hex: 0x24425F)
    static let blue = Color(hex: 0x3D6286)
    static let blueButton = Color(hex: 0x355A80)
    static let blueRing = Color(hex: 0x9DBAD8)
    static let blueSoft = Color(hex: 0xE5EEF7)

    static let tan = Color(hex: 0xF4EBDA)
    static let tanInk = Color(hex: 0x5B4426)
    static let tanStrong = Color(hex: 0xD9B98A)
    static let brown = Color(hex: 0x7A5A3A)
    static let sand = Color(hex: 0xF2ECE0)
    static let sandDeep = Color(hex: 0xEFE8DC)
    static let paper = Color(hex: 0xF4EEE3)
    static let avatar = Color(hex: 0xE9EFE3)
    static let barIdle = Color(hex: 0xE3DBCD)
    static let waveIdle = Color(hex: 0xCFC6B6)
}

extension Font {
    /// Figtree, the design's UI face. Scales with Dynamic Type relative to `style`.
    static func figtree(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        if weight == .heavy || weight == .black {
            name = "Figtree-ExtraBold"
        } else if weight == .bold {
            name = "Figtree-Bold"
        } else if weight == .semibold {
            name = "Figtree-SemiBold"
        } else if weight == .medium {
            name = "Figtree-Medium"
        } else {
            name = "Figtree-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Courier Prime: how Tuk "talks" in speech bubbles.
    static func tuk(_ size: CGFloat = 15, bold: Bool = false) -> Font {
        .custom(bold ? "CourierPrime-Bold" : "CourierPrime-Regular", size: size, relativeTo: .body)
    }
}

// MARK: - Shapes and surfaces

/// Tuk's speech bubble: rounded, with a small tail corner at the bottom left.
struct TukBubbleShape: Shape {
    var radius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: 6,
            bottomTrailingRadius: radius,
            topTrailingRadius: radius + 2,
            style: .continuous
        )
        .path(in: rect)
    }
}

/// The user's own bubble in Coach: tail corner at the bottom right.
struct MyBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 6,
            topTrailingRadius: 20,
            style: .continuous
        )
        .path(in: rect)
    }
}

extension View {
    /// White card with a hairline border, used for most sections.
    func liftrCard(radius: CGFloat = 24, fill: Color = Palette.card) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }

    /// Text in one of Tuk's speech bubbles.
    func tukBubble(radius: CGFloat = 22) -> some View {
        font(.tuk())
            .foregroundStyle(Palette.tukInk)
            .lineSpacing(3)
            .background(Color.white, in: TukBubbleShape(radius: radius))
            .overlay(TukBubbleShape(radius: radius).stroke(Palette.outline, lineWidth: 1.5))
    }

    /// Leaves room at the bottom for the floating tab bar.
    func tabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: LiftrTabBar.clearance) }
    }
}

/// Buttons shrink a touch when pressed, like the prototype's `.lf-press`.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Small shared pieces

/// "A slip moves Tuk back one step at most." with the leaf icon.
struct LeafNote: View {
    var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "leaf")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.green)
            Text(text)
                .font(.figtree(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Small rounded label like "+18 this week".
struct Pill: View {
    var text: String
    var foreground = Palette.green
    var background = Palette.greenSoft

    var body: some View {
        Text(text)
            .font(.figtree(12, .heavy, relativeTo: .caption))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

/// A tag button that can be toggled, used for triggers and invite options.
struct ChoiceChip: View {
    var label: String
    var isOn: Bool
    var height: CGFloat = 36
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.figtree(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(isOn ? Palette.onGreen : Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: height)
                .background(isOn ? Palette.green : Palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Palette.green : Palette.chipBorder, lineWidth: 1.5))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Voice-note style bars. `progress` (0...1) colours the played part.
struct WaveformBars: View {
    static let pattern: [CGFloat] = [6, 10, 15, 9, 17, 21, 13, 8, 14, 19, 11, 7, 12, 17, 21, 15, 9, 11, 17, 13, 7, 10, 15, 19, 12, 8, 6, 9]

    var count = 28
    var progress: Double = 0
    var idle = Palette.waveIdle
    var played = Palette.green
    var maxHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                let height = Self.pattern[index % Self.pattern.count] * maxHeight / 22
                RoundedRectangle(cornerRadius: 2)
                    .fill(Double(index) / Double(count) < progress ? played : idle)
                    .frame(width: 3, height: height)
            }
        }
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }
}

/// Lays children out left to right and wraps onto new lines, for chip groups.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = self.rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
