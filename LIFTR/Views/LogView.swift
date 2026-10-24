//
//  LogView.swift
//  LIFTR
//

import SwiftUI

/// Log it: one tap per cigarette, vape or pouch, or one sentence by voice. No judgment.
struct LogView: View {
    @Environment(CheckInStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var voice = QuickVoiceLog()
    @State private var last: LastLog?
    @State private var didUndo = false
    @State private var showingManualLog = false
    @State private var errorMessage: String?

    static let triggers = ["Stress", "Coffee", "After a meal", "Friends", "Bored", "Other"]

    /// What was logged most recently, so it can be tagged or undone.
    struct LastLog: Equatable {
        var id = UUID()
        var product: Product
        var count: Int
        var events: [LogEvent]
        var byVoice: Bool
        var trigger: String?
    }

    var body: some View {
        let progress = store.progress
        ScrollView {
            VStack(spacing: 14) {
                header
                HStack(spacing: 10) {
                    productButton(.cigarette, count: progress.cigarettesToday ?? 0)
                    productButton(.vape, count: progress.vapesToday)
                    productButton(.pouch, count: progress.pouchesToday)
                }
                voiceCard
                if let errorMessage {
                    Text(errorMessage)
                        .font(.figtree(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.tanInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                if let last {
                    confirmation(last, stage: progress.stage)
                        .id(last.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                } else {
                    emptyCard
                        .transition(.opacity)
                }
                Button("Log a different day") { showingManualLog = true }
                    .font(.figtree(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.green)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .animation(.spring(duration: 0.45), value: last)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .tabBarClearance()
        .sheet(isPresented: $showingManualLog) { ManualLogView() }
        .onDisappear { voice.cancel() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Log it")
                    .font(.figtree(30, .heavy, relativeTo: .largeTitle))
                    .tracking(-0.3)
                Text("One tap. No judgment.\nEach log helps Tuk learn.")
                    .font(.figtree(15, relativeTo: .body))
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            Button {
                router.showingCravingHelp = true
            } label: {
                Label("Craving help", systemImage: "wind")
                    .font(.figtree(14, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Palette.skyInk)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Palette.sky, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.skyBorder, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .padding(.top, 4)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 4)
    }

    private func productButton(_ product: Product, count: Int) -> some View {
        Button {
            log(product, count: 1, byVoice: false)
        } label: {
            VStack(spacing: 7) {
                ProductIcon(product: product)
                Text(product.title)
                    .font(.figtree(15, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text("\(count) today")
                    .font(.figtree(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
                    .contentTransition(.numericText(value: Double(count)))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .liftrCard()
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.impact(weight: .light), trigger: count)
        .accessibilityLabel("Log a \(product.noun(1))")
        .accessibilityValue("\(count) today")
    }

    // MARK: - Voice

    private var voiceCard: some View {
        let isListening = voice.state == .listening
        return HStack(spacing: 18) {
            ZStack {
                if isListening {
                    PulseRings(color: Palette.greenPulse, size: 88)
                }
                Button {
                    toggleVoice()
                } label: {
                    Image(systemName: isListening ? "stop.fill" : "mic")
                        .font(.system(size: isListening ? 26 : 30, weight: .regular))
                        .foregroundStyle(Palette.onGreen)
                        .frame(width: 88, height: 88)
                        .background(Palette.green, in: Circle())
                        .shadow(color: Palette.green.opacity(0.5), radius: 10, y: 8)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(isListening ? "Stop listening" : "Log by voice")
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 5) {
                if isListening {
                    Text("Listening…")
                        .font(.figtree(17, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.green)
                    Text(voice.transcript.isEmpty ? "Say something like “two cigarettes”" : voice.transcript)
                        .font(.tuk())
                        .foregroundStyle(Palette.tukInk)
                        .lineLimit(3)
                } else {
                    Text("Or just say it")
                        .font(.figtree(17, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    if case let .failed(message) = voice.state {
                        Text(message)
                            .font(.figtree(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.tanInk)
                    } else {
                        Text("Tap the mic and talk, like:")
                            .font(.figtree(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSecondary)
                        Text("“I smoked three cigarettes”")
                            .font(.tuk())
                            .foregroundStyle(Palette.tukInk)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .liftrCard(radius: 26)
        .animation(.easeOut(duration: 0.2), value: isListening)
    }

    private func toggleVoice() {
        if voice.state == .listening {
            voice.finish()
            return
        }
        errorMessage = nil
        Task {
            await voice.start { sentence in
                let counts = VoiceLogParser.parse(sentence)
                guard !counts.isEmpty else {
                    errorMessage = "I heard “\(sentence)” but there was nothing to log. Try “two cigarettes”."
                    return
                }
                // One sentence can mention several things. Log the biggest last so the card shows it.
                let ordered = counts.sorted { $0.value < $1.value }
                for (index, entry) in ordered.enumerated() {
                    log(entry.key, count: entry.value, byVoice: true, showCard: index == ordered.count - 1)
                }
            }
        }
    }

    // MARK: - Logging

    private func log(_ product: Product, count: Int, byVoice: Bool, showCard: Bool = true) {
        do {
            let events = try store.logUse(product, count: count, source: byVoice ? "voice" : "manual")
            errorMessage = nil
            didUndo = false
            if showCard {
                last = LastLog(product: product, count: count, events: events, byVoice: byVoice)
            }
        } catch {
            errorMessage = "Couldn't save that: \(error.localizedDescription)"
        }
    }

    private func undo(_ entry: LastLog) {
        do {
            try store.undo(entry.events)
            last = nil
            didUndo = true
        } catch {
            errorMessage = "Couldn't undo that: \(error.localizedDescription)"
        }
    }

    private func pick(_ trigger: String, for entry: LastLog) {
        let newValue = entry.trigger == trigger ? nil : trigger
        store.setTrigger(newValue, for: entry.events)
        last?.trigger = newValue
    }

    // MARK: - Cards

    private func confirmation(_ entry: LastLog, stage: TukStage) -> some View {
        let today = entry.product == .cigarette ? (store.progress.cigarettesToday ?? 0)
            : entry.product == .vape ? store.progress.vapesToday : store.progress.pouchesToday
        let title: String
        let line: String
        switch (entry.product, entry.byVoice) {
        case (_, true):
            title = "Logged \(entry.count) · \(today) today"
            line = "Got it, \(entry.count == 1 ? "one" : "\(entry.count)"). Thanks for being honest. What was going on?"
        case (.cigarette, false):
            title = "Logged · \(today) today"
            line = "I had one with you. What set it off?"
        case (.vape, false):
            title = "Vape logged · \(today) today"
            line = "Noted, no judgment. What was going on?"
        case (.pouch, false):
            title = "Pouch logged · \(today) today"
            line = "Noted. What was going on right before?"
        }
        // Tuk smokes along after a cigarette or vape, like the design's stage-1 loop.
        let tukStage: TukStage = entry.product == .pouch ? stage : .smoking

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TukView(stage: tukStage)
                    .frame(width: 92, height: 92)
                    .frame(width: 96, height: 96)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.figtree(17, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    Text(line)
                        .font(.tuk())
                        .foregroundStyle(Palette.tukInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FlowLayout(spacing: 8) {
                ForEach(Self.triggers, id: \.self) { trigger in
                    ChoiceChip(label: trigger, isOn: entry.trigger == trigger) { pick(trigger, for: entry) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What set it off?")

            if let trigger = entry.trigger {
                (Text("Noted: \(trigger.lowercased()). We'll look at it together in ")
                    + Text("Coach").font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundColor(Palette.green)
                    + Text("."))
                    .font(.figtree(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .onTapGesture { router.tab = .coach }
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                LeafNote(text: "A slip moves Tuk back one step at most. Never to the start.")
                Spacer(minLength: 0)
                Button("Undo") { undo(entry) }
                    .font(.figtree(14, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Palette.green)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Line().stroke(Palette.dashed, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .liftrCard(radius: 26)
        .animation(.easeOut(duration: 0.25), value: entry.trigger)
    }

    private var emptyCard: some View {
        HStack(spacing: 12) {
            TukStage.cuttingDown.image
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(didUndo ? "Undone. I'm here whenever you need to log." : "I'm here whenever you need to log.")
                .font(.tuk())
                .foregroundStyle(Palette.tukInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// The little drawings on the Cigarette, Vape and Pouch buttons.
struct ProductIcon: View {
    var product: Product

    var body: some View {
        ZStack {
            Circle().fill(background)
            Canvas { context, size in
                let scale = size.width / 32
                context.scaleBy(x: scale, y: scale)
                let ink = Color(hex: 0x2E2823)
                switch product {
                case .cigarette:
                    var smoke = Path()
                    smoke.move(to: CGPoint(x: 25, y: 9))
                    smoke.addCurve(to: CGPoint(x: 24, y: 2.5), control1: CGPoint(x: 23, y: 7), control2: CGPoint(x: 26, y: 5))
                    context.stroke(smoke, with: .color(Color(hex: 0xA19D97)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    context.translateBy(x: 16, y: 17)
                    context.rotate(by: .degrees(-28))
                    context.translateBy(x: -16, y: -17)
                    let body = Path(roundedRect: CGRect(x: 3, y: 14.5, width: 25, height: 5.4), cornerRadius: 2.2)
                    context.fill(body, with: .color(Color(hex: 0xFFFEFB)))
                    context.stroke(body, with: .color(ink), lineWidth: 1.6)
                    let filter = Path(roundedRect: CGRect(x: 3, y: 14.5, width: 7.5, height: 5.4), cornerRadius: 1.8)
                    context.fill(filter, with: .color(Color(hex: 0xE8C69A)))
                    context.stroke(filter, with: .color(ink), lineWidth: 1.4)
                    context.fill(Path(roundedRect: CGRect(x: 25, y: 15, width: 3, height: 4.4), cornerRadius: 1.2), with: .color(Color(hex: 0xF2A65A)))
                case .vape:
                    context.translateBy(x: 16, y: 16)
                    context.rotate(by: .degrees(32))
                    context.translateBy(x: -16, y: -16)
                    let body = Path(roundedRect: CGRect(x: 12, y: 2.5, width: 8, height: 27), cornerRadius: 4)
                    context.fill(body, with: .color(Color(hex: 0xA9C8E6)))
                    context.stroke(body, with: .color(ink), lineWidth: 1.6)
                    let tip = Path(roundedRect: CGRect(x: 13.4, y: 2.5, width: 5.2, height: 6), cornerRadius: 2.4)
                    context.fill(tip, with: .color(Color(hex: 0xF2ECE0)))
                    context.stroke(tip, with: .color(ink), lineWidth: 1.4)
                    context.fill(Path(ellipseIn: CGRect(x: 14.5, y: 19.5, width: 3, height: 3)), with: .color(ink))
                case .pouch:
                    var side = Path()
                    side.move(to: CGPoint(x: 5, y: 13.5))
                    side.addLine(to: CGPoint(x: 5, y: 19))
                    side.addCurve(to: CGPoint(x: 27, y: 19), control1: CGPoint(x: 5, y: 25.7), control2: CGPoint(x: 27, y: 25.7))
                    side.addLine(to: CGPoint(x: 27, y: 13.5))
                    context.fill(side, with: .color(Color(hex: 0xBFD3B6)))
                    context.stroke(side, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    let lid = Path(ellipseIn: CGRect(x: 5, y: 8.5, width: 22, height: 10))
                    context.fill(lid, with: .color(Color(hex: 0xE3EBDD)))
                    context.stroke(lid, with: .color(ink), lineWidth: 1.6)
                    var mark = Path()
                    mark.move(to: CGPoint(x: 11, y: 13.6))
                    mark.addCurve(to: CGPoint(x: 21, y: 13.6), control1: CGPoint(x: 13, y: 12), control2: CGPoint(x: 19, y: 12))
                    context.stroke(mark, with: .color(ink.opacity(0.6)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            }
            .frame(width: 34, height: 34)
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
    }

    private var background: Color {
        switch product {
        case .cigarette: Palette.tan
        case .vape: Palette.blueSoft
        case .pouch: Palette.greenSoft
        }
    }
}

/// Two soft rings that grow and fade, behind a listening mic.
struct PulseRings: View {
    var color: Color
    var size: CGFloat
    var cornerRadius: CGFloat?

    @State private var animate = false

    var body: some View {
        ZStack {
            ring(delay: 0)
            ring(delay: 0.6)
        }
        .onAppear { animate = true }
        .accessibilityHidden(true)
    }

    private func ring(delay: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous)
            .fill(color)
            .scaleEffect(animate ? 1.8 : 1)
            .opacity(animate ? 0 : 0.5)
            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(delay), value: animate)
    }
}

/// A horizontal line across the frame, for dashed dividers.
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
