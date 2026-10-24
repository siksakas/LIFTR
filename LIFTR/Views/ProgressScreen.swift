//
//  ProgressScreen.swift
//  LIFTR
//

import Charts
import SwiftUI

/// Progress: the LIFTR Score and how it's built, the weekly trend, when cravings hit,
/// and Tuk's path through the five stages.
struct ProgressScreen: View {
    @Environment(CheckInStore.self) private var store
    @Environment(Reminders.self) private var reminders
    @State private var previewStage: TukStage?

    var body: some View {
        let progress = store.progress
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Progress")
                        .font(.figtree(30, .heavy, relativeTo: .largeTitle))
                        .tracking(-0.3)
                        .foregroundStyle(Palette.ink)
                    Text("Day \(progress.dayNumber()) with Tuk. Slow and steady counts.")
                        .font(.figtree(15, relativeTo: .body))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                ScoreCard(progress: progress)
                WeeklyTrendCard(weeks: progress.weeklyScores)
                cravingsCard
                pathCard(progress)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .tabBarClearance()
    }

    // MARK: - When cravings hit

    private var cravingsCard: some View {
        let patterns = store.patterns
        let counts = patterns.last30Days
        let peak = max(counts.values.max() ?? 0, 1)
        let top = patterns.toughestWindow
        let second = patterns.secondWindow
        let window = reminders.breatherEnabled ? reminders.breatherWindow : (top ?? .afternoon)

        return VStack(alignment: .leading, spacing: 12) {
            cardTitle("When cravings hit", detail: "Last 30 days")

            if counts.isEmpty {
                Text("Log when you smoke or open craving help, and Tuk will spot the times of day that are hardest.")
                    .font(.figtree(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 2)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(UsagePatterns.Window.allCases) { slot in
                        let count = counts[slot] ?? 0
                        let color = slot == top ? Palette.blue : slot == second ? Palette.tanStrong : Palette.barIdle
                        let numberColor = slot == top ? Palette.skyInk : slot == second ? Palette.brown : Palette.inkSecondary
                        VStack(spacing: 5) {
                            Text("\(count)")
                                .font(.figtree(11, .heavy, relativeTo: .caption2))
                                .foregroundStyle(numberColor)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(color)
                                .frame(height: 4 + 74 * CGFloat(count) / CGFloat(peak))
                            Text(slot.shortLabel)
                                .font(.figtree(10, .heavy, relativeTo: .caption2))
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 118, alignment: .bottom)
                .padding(.horizontal, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cravingsSummary(counts: counts, top: top))

                HStack(spacing: 8) {
                    if let top {
                        windowChip(top, trigger: patterns.topTriggers[top], dot: Palette.blue, foreground: Palette.skyInk, background: Palette.blueSoft)
                    }
                    if let second {
                        windowChip(second, trigger: patterns.topTriggers[second], dot: Color(hex: 0xB9874D), foreground: Palette.tanInk, background: Palette.tan)
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { reminders.breatherEnabled },
                set: { on in Task { await reminders.setBreather(on, window: window) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.breatherName)
                        .font(.figtree(14, .heavy, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                    Text(reminders.breatherSummary(for: window))
                        .font(.figtree(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .tint(Palette.green)
            .padding(.top, 12)
            .padding(.horizontal, 2)
            .overlay(alignment: .top) {
                Line().stroke(Palette.dashed, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .liftrCard(radius: 26)
    }

    private func windowChip(_ window: UsagePatterns.Window, trigger: String?, dot: Color, foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(trigger.map { "\(window.chipLabel) · \($0.lowercased())" } ?? window.chipLabel)
                .lineLimit(1)
        }
        .font(.figtree(13, .heavy, relativeTo: .footnote))
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(background, in: Capsule())
    }

    private func cravingsSummary(counts: [UsagePatterns.Window: Int], top: UsagePatterns.Window?) -> String {
        guard let top else { return "No logs yet." }
        return "Logs by time of day. \(top.label) is the highest, with \(counts[top] ?? 0) logs."
    }

    // MARK: - Tuk's path

    private func pathCard(_ progress: RecoveryProgress) -> some View {
        let current = progress.stage
        let selected = previewStage ?? current

        return VStack(alignment: .leading, spacing: 12) {
            cardTitle("Tuk's path", detail: "Tap a stage to preview")

            HStack(spacing: 10) {
                TukView(stage: selected)
                    .frame(width: 146, height: 146)
                VStack(alignment: .leading, spacing: 5) {
                    Text(status(of: selected, current: current, highest: progress.highestStage))
                        .font(.figtree(12, .heavy, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(selected.title)
                        .font(.figtree(18, .heavy, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text("Score \(selected.scoreRange.lowerBound)–\(selected.scoreRange.upperBound)")
                        .font(.figtree(12, .bold, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(selected.pathLine)
                        .font(.tuk(13.5))
                        .foregroundStyle(Palette.tukInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
            .padding(.trailing, 14)
            .frame(height: 150)
            .background(selected.previewColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.easeInOut(duration: 1.2), value: selected)
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: 4) {
                ForEach(TukStage.allCases) { stage in
                    stageButton(stage, selected: selected, current: current, highest: progress.highestStage)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(alignment: .top) {
                Line()
                    .stroke(Color(hex: 0xCFC4B1), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(height: 2)
                    .padding(.horizontal, 30)
                    .padding(.top, 28)
            }
            .padding(.horizontal, 2)

            LeafNote(text: "A slip moves Tuk back one step at most. Never to the start.")
        }
        .padding(16)
        .liftrCard(radius: 26)
    }

    private func stageButton(_ stage: TukStage, selected: TukStage, current: TukStage, highest: TukStage) -> some View {
        let isSelected = stage == selected
        let isCurrent = stage == current
        let border: StrokeStyle = stage > highest ? StrokeStyle(lineWidth: 2, dash: [4, 3]) : StrokeStyle(lineWidth: isSelected ? 3 : 2)
        let borderColor = isSelected ? Palette.green : stage > highest ? Color(hex: 0xC9BDA8) : Color(hex: 0xA9BFA0)

        return Button {
            previewStage = stage
        } label: {
            VStack(spacing: 5) {
                stage.headImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .background(Palette.avatar)
                    .clipShape(Circle())
                    .overlay(Circle().inset(by: border.lineWidth / 2).stroke(borderColor, style: border))
                    .background {
                        if isSelected { Circle().fill(Palette.greenSoft).padding(-4) }
                    }
                Text(isCurrent ? "You're here" : "\(stage.rawValue)")
                    .font(.figtree(11, .heavy, relativeTo: .caption2))
                    .foregroundStyle(isCurrent ? Palette.green : Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview stage \(stage.rawValue), \(stage.title)\(isCurrent ? ", you're here" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func status(of stage: TukStage, current: TukStage, highest: TukStage) -> String {
        if stage == current { return "You're here" }
        return stage <= highest ? "Reached" : "Ahead"
    }

    private func cardTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.figtree(16, .heavy, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(detail)
                .font(.figtree(12, .bold, relativeTo: .caption))
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Score

private struct ScoreCard: View {
    var progress: RecoveryProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LIFTR Score")
                    .font(.figtree(13, .heavy, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                ScoreChangePill(change: progress.scoreChangeThisWeek)
            }

            ScoreGauge(score: progress.score, stage: progress.stage, pointsToNext: progress.pointsToNextStage)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("How it's built")
                    .font(.figtree(13, .heavy, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Palette.green.frame(width: (proxy.size.width - 2) * RecoveryProgress.recentWeight)
                        Palette.tanStrong
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                HStack {
                    (Text("\(Int(RecoveryProgress.recentWeight * 100))%").font(.figtree(13, .heavy, relativeTo: .footnote)).foregroundColor(Palette.ink)
                        + Text(" your last 3 months"))
                    Spacer()
                    (Text("\(Int((1 - RecoveryProgress.recentWeight) * 100))%").font(.figtree(13, .heavy, relativeTo: .footnote)).foregroundColor(Palette.ink)
                        + Text(" since day one"))
                }
                .font(.figtree(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSecondary)
                LeafNote(text: "A slip nudges it down a little. It never wipes it out.")
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .liftrCard(radius: 26)
    }
}

/// The big half-circle gauge, banded by Tuk's five stages.
private struct ScoreGauge: View {
    var score: Int
    var stage: TukStage
    var pointsToNext: Int?

    @State private var drawn = 0.0

    private static let bands: [UInt32] = [0xDDD6CA, 0xE6D7B9, 0xDCE5CD, 0xCFE2C2, 0xEFE0B4]
    private static let radius: CGFloat = 120
    private static let size = CGSize(width: 300, height: 160)
    private static let center = CGPoint(x: 150, y: 140)

    var body: some View {
        let fraction = RecoveryProgress.fraction(of: score)
        ZStack(alignment: .topLeading) {
            ForEach(TukStage.allCases) { band in
                let range = band.scoreRange
                let from = RecoveryProgress.fraction(of: range.lowerBound)
                let to = band.next == nil ? 1 : RecoveryProgress.fraction(of: range.upperBound + 1) - 0.006
                arc(from: from, to: to, color: Color(hex: Self.bands[band.rawValue - 1]), lineWidth: 16, cap: .butt)
            }
            arc(from: 0, to: drawn, color: Palette.green, lineWidth: 8, cap: .round)
            Circle()
                .fill(Palette.card)
                .overlay(Circle().strokeBorder(Palette.green, lineWidth: 4))
                .frame(width: 22, height: 22)
                .position(SemiArc.point(at: drawn, center: Self.center, radius: Self.radius))

            Text("300")
                .position(x: 30, y: 154)
            Text("850")
                .position(x: 270, y: 154)

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.figtree(54, .heavy, relativeTo: .largeTitle))
                    .tracking(-1.6)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(score)))
                Text(stage.title)
                    .font(.figtree(15, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.green)
                if let pointsToNext, let next = stage.next {
                    Text("\(pointsToNext) points to \(next.title)")
                        .font(.figtree(12, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(width: Self.size.width)
            .padding(.top, 60)
        }
        .font(.figtree(11, .bold, relativeTo: .caption2))
        .foregroundStyle(Palette.inkSecondary)
        .frame(width: Self.size.width, height: Self.size.height + 11, alignment: .topLeading)
        .onAppear {
            withAnimation(.timingCurve(0.3, 0.7, 0.2, 1, duration: 1.6).delay(0.25)) { drawn = fraction }
        }
        .onChange(of: score) {
            withAnimation(.easeInOut(duration: 1)) { drawn = RecoveryProgress.fraction(of: score) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LIFTR Score \(score) out of 850. \(stage.title).")
    }

    /// Part of the arc. It sits in a 240 x 120 box so its centre lands at (150, 140).
    private func arc(from: Double, to: Double, color: Color, lineWidth: CGFloat, cap: CGLineCap) -> some View {
        SemiArc()
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: cap))
            .frame(width: Self.radius * 2, height: Self.radius)
            .offset(x: Self.center.x - Self.radius, y: Self.center.y - Self.radius)
    }
}

// MARK: - Weekly trend

private struct WeeklyTrendCard: View {
    var weeks: [RecoveryProgress.WeekScore]

    private struct Point: Identifiable {
        var id: Int
        var label: String
        var score: Int
        var isSlip: Bool
        var isNow: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your score, week by week")
                    .font(.figtree(16, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(max(weeks.count, 1)) week\(weeks.count == 1 ? "" : "s")")
                    .font(.figtree(12, .bold, relativeTo: .caption))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, 2)

            if weeks.count < 2 {
                Text("Your weekly trend shows up after your first week with Tuk.")
                    .font(.figtree(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 8)
            } else {
                chart
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .liftrCard(radius: 26)
    }

    private var points: [Point] {
        // The biggest weekly drop, if any, is called out as a slip week.
        let drops = weeks.indices.dropFirst().map { ($0, weeks[$0].score - weeks[$0 - 1].score) }
        let slip = drops.filter { $0.1 < 0 }.min { $0.1 < $1.1 }?.0
        return weeks.enumerated().map { index, week in
            Point(
                id: index,
                label: week.weeksAgo == 0 ? "Now" : "Wk \(index + 1)",
                score: week.score,
                isSlip: index == slip,
                isNow: week.weeksAgo == 0
            )
        }
    }

    private var chart: some View {
        let points = self.points
        let scores = points.map(\.score)
        let low = Int((Double((scores.min() ?? 300) - 20) / 20).rounded(.down)) * 20
        let high = Int((Double((scores.max() ?? 850) + 20) / 20).rounded(.up)) * 20
        let step = max(20, Int((Double(high - low) / 3 / 10).rounded(.up)) * 10)
        let ticks = Array(stride(from: low, through: high, by: step))
        let slipDrop = points.firstIndex(where: \.isSlip).map { points[$0].score - points[$0 - 1].score }

        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Week", point.label),
                    yStart: .value("Floor", low),
                    yEnd: .value("Score", point.score)
                )
                .foregroundStyle(Palette.greenSoft.opacity(0.75))
                .interpolationMethod(.catmullRom)

                LineMark(x: .value("Week", point.label), y: .value("Score", point.score))
                    .foregroundStyle(Palette.green)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                PointMark(x: .value("Week", point.label), y: .value("Score", point.score))
                    .symbol {
                        if point.isNow {
                            Circle().fill(Palette.green).overlay(Circle().stroke(Palette.card, lineWidth: 2.4)).frame(width: 12, height: 12)
                        } else {
                            Circle().fill(Palette.card).overlay(Circle().stroke(point.isSlip ? Color(hex: 0xB07A3C) : Palette.green, lineWidth: 2.2)).frame(width: 9, height: 9)
                        }
                    }
                    .annotation(position: point.isSlip ? .bottom : .top, spacing: 6) {
                        if point.isNow {
                            Text("\(point.score)")
                                .font(.figtree(12, .heavy, relativeTo: .caption))
                                .foregroundStyle(Palette.ink)
                        } else if point.isSlip, let slipDrop {
                            Text("Slip week, −\(-slipDrop)")
                                .font(.figtree(11, .heavy, relativeTo: .caption2))
                                .foregroundStyle(Palette.brown)
                                .fixedSize()
                        }
                    }
            }
        }
        .chartYScale(domain: low...high)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Color(hex: 0xE6DED0))
                AxisValueLabel()
                    .font(.figtree(10, .bold, relativeTo: .caption2))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.figtree(10, .bold, relativeTo: .caption2))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(height: 150)
        .accessibilityLabel("Score went from \(scores.first ?? 0) to \(scores.last ?? 0) over \(scores.count) weeks.")
    }
}
