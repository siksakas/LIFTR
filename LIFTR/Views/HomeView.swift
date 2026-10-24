//
//  HomeView.swift
//  LIFTR
//

import SwiftUI

/// Home: Tuk's little world, what Tuk has to say, today's count and the LIFTR Score.
struct HomeView: View {
    @Environment(CheckInStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var pokes = 0
    @State private var showingReminders = false

    var body: some View {
        let progress = store.progress
        let day = progress.dayNumber()
        ScrollView {
            VStack(spacing: 10) {
                header(day: day)
                world(stage: progress.stage, day: day)
                tukSays(stage: progress.stage)
                HStack(spacing: 12) {
                    todayCard(progress)
                    scoreCard(progress)
                }
                .fixedSize(horizontal: false, vertical: true)
                cravingButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .tabBarClearance()
        .sheet(isPresented: $showingReminders) {
            RemindersSheet()
        }
    }

    private func header(day: Int) -> some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("LIFTR")
                    .font(.figtree(15, .heavy, relativeTo: .headline))
                    .tracking(3.3)
                Text("Day \(day) with Tuk")
                    .font(.figtree(13, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            Button {
                showingReminders = true
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Palette.card, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Check-ins and reminders")
        }
        .frame(height: 44)
        .padding(.leading, 4)
        .foregroundStyle(Palette.ink)
    }

    private func world(stage: TukStage, day: Int) -> some View {
        TukView(stage: stage, showsScene: true)
            .frame(height: 306)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    badge {
                        Text("Day \(day)").font(.figtree(13, .heavy, relativeTo: .footnote))
                    }
                    badge {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(stage.shellColor)
                                .overlay(Circle().strokeBorder(Color(hex: 0x2E2823), lineWidth: 1))
                                .frame(width: 9, height: 9)
                            Text("Stage \(stage.rawValue) · \(stage.title)").font(.figtree(13, .semibold, relativeTo: .footnote))
                        }
                    }
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color(hex: 0xE3D9C7), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.5)) { pokes += 1 }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Say hi to Tuk")
    }

    private func badge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(hex: 0xFFFEFB, opacity: 0.86), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.14), lineWidth: 1))
    }

    private func tukSays(stage: TukStage) -> some View {
        let message = homeMessage
        return HStack(alignment: .bottom, spacing: 10) {
            TukAvatar(stage: stage)
            Text(message)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tukBubble()
                .id(message)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 66, alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tuk says: \(message)")
    }

    private var homeMessage: String {
        switch pokes % 3 {
        case 1: return "I'm right here. One breath at a time."
        case 2: return "Small steps still count. Want a breather together?"
        default: break
        }
        let progress = store.progress
        guard progress.firstDay != nil else {
            return "Hi, I'm Tuk. Log when you smoke and I'll learn alongside you. No judgment."
        }
        let day = "Day \(progress.dayNumber())."
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        if let today = progress.cigarettesToday,
           let lastWeek = store.log(for: weekAgo),
           today < lastWeek.cigarettesSmoked {
            let weekday = weekAgo.formatted(.dateTime.weekday(.wide))
            return "\(day) Fewer cigarettes than last \(weekday). I'm breathing easier too."
        }
        return "\(day) \(progress.stage.homeLine)"
    }

    private func todayCard(_ progress: RecoveryProgress) -> some View {
        let count = progress.cigarettesToday ?? 0
        return Button {
            router.tab = .log
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("Today")
                    .font(.figtree(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(count)")
                        .font(.figtree(36, .heavy, relativeTo: .largeTitle))
                        .tracking(-0.7)
                    Text(Product.cigarette.noun(count))
                        .font(.figtree(14, .bold, relativeTo: .subheadline))
                }
                Text(usualLine(progress))
                    .font(.figtree(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Vape \(progress.vapesToday) · Pouch \(progress.pouchesToday)")
                    .font(.figtree(12, .bold, relativeTo: .caption))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .liftrCard(radius: 22)
        }
        .buttonStyle(.pressable)
    }

    private func usualLine(_ progress: RecoveryProgress) -> String {
        if let usual = store.patterns.usualCigarettesByNow {
            return "Usually \(Int(usual.rounded())) by now"
        }
        if progress.firstDay != nil {
            return "Your usual is about \(Int(progress.baseline.rounded())) a day"
        }
        return "Tap Log when you have one"
    }

    private func scoreCard(_ progress: RecoveryProgress) -> some View {
        Button {
            router.tab = .progress
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("LIFTR Score")
                        .font(.figtree(13, .bold, relativeTo: .footnote))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Palette.inkSecondary)
                HStack(alignment: .bottom, spacing: 6) {
                    Text("\(progress.score)")
                        .font(.figtree(36, .heavy, relativeTo: .largeTitle))
                        .tracking(-0.7)
                        .contentTransition(.numericText(value: Double(progress.score)))
                    Spacer(minLength: 0)
                    MiniScoreGauge(score: progress.score)
                }
                Text("out of 850")
                    .font(.figtree(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 0)
                ScoreChangePill(change: progress.scoreChangeThisWeek)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .liftrCard(radius: 22)
        }
        .buttonStyle(.pressable)
        .animation(.default, value: progress.score)
    }

    private var cravingButton: some View {
        Button {
            router.showingCravingHelp = true
        } label: {
            Label("Craving? Breathe with Tuk", systemImage: "wind")
                .font(.figtree(16, .heavy, relativeTo: .headline))
                .foregroundStyle(Palette.skyInk)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Palette.sky, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.skyBorder, lineWidth: 1.5))
        }
        .buttonStyle(.pressable)
    }
}

/// "+18 this week", "−5 this week", or "Starting point" in the first week.
struct ScoreChangePill: View {
    var change: Int?

    var body: some View {
        if let change {
            if change >= 0 {
                Pill(text: "+\(change) this week")
            } else {
                Pill(text: "−\(-change) this week", foreground: Palette.tanInk, background: Palette.tan)
            }
        } else {
            Pill(text: "Starting point", foreground: Palette.inkSecondary, background: Palette.sand)
        }
    }
}
