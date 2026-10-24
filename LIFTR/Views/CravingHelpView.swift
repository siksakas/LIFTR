//
//  CravingHelpView.swift
//  LIFTR
//

import SwiftData
import SwiftUI

/// Craving help: one minute of breathing with Tuk, a voice note from someone who cares,
/// or a quick talk with Tuk.
struct CravingHelpView: View {
    enum Phase {
        case idle, breatheIn, hold, breatheOut, done

        var label: String {
            switch self {
            case .idle: "Breathe with Tuk"
            case .breatheIn: "Breathe in…"
            case .hold: "Hold"
            case .breatheOut: "And out, slowly…"
            case .done: "Nice. That was one minute."
            }
        }
    }

    @Environment(CheckInStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Encouragement.createdAt, order: .reverse) private var encouragements: [Encouragement]

    @State private var phase = Phase.idle
    @State private var breathing: Task<Void, Never>?
    @State private var ringScale = 0.86
    @State private var glow = 0.0
    @State private var player = VoiceNotePlayer()
    @State private var loggedCraving = false

    private var isRunning: Bool { breathing != nil }

    var body: some View {
        let stage = max(store.progress.stage, .cuttingDown)
        ScrollView {
            VStack(spacing: 12) {
                header
                VStack(spacing: 6) {
                    Text("You're okay.\nLet's ride this one out.")
                        .font(.figtree(25, .heavy, relativeTo: .title))
                        .tracking(-0.25)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink)
                    Text("Cravings usually pass in a few minutes.")
                        .font(.figtree(15, relativeTo: .body))
                        .foregroundStyle(Color(hex: 0x4B5560))
                }
                breathingCircle(stage: stage)
                VStack(spacing: 6) {
                    startButton
                    Text("In for 4 · hold for 1 · out for 5")
                        .font(.figtree(13, relativeTo: .footnote))
                        .foregroundStyle(Color(hex: 0x4B5560))
                }
                otherHelp(stage: stage)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { background }
        .onDisappear {
            breathing?.cancel()
            player.stop()
        }
    }

    private var header: some View {
        ZStack {
            Text("Craving help")
                .font(.figtree(15, .heavy, relativeTo: .headline))
                .foregroundStyle(Palette.skyInk)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(Color(hex: 0xFFFEFB, opacity: 0.9), in: Circle())
                        .overlay(Circle().strokeBorder(Color(hex: 0xD5E0EA), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.top, 6)
    }

    private func breathingCircle(stage: TukStage) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)], center: .center, startRadius: 0, endRadius: 83))
                    .frame(width: 236, height: 236)
                    .scaleEffect(0.7 + 0.4 * glow)
                    .opacity(0.7 * glow)
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .overlay(Circle().strokeBorder(Palette.blueRing, lineWidth: 1.5))
                    .frame(width: 224, height: 224)
                    .scaleEffect(ringScale)
                TukView(stage: stage, mode: isRunning ? .breathe : .loop)
                    .frame(width: 176, height: 176)
            }
            .frame(height: 240)

            Text(phase.label)
                .font(.figtree(21, .heavy, relativeTo: .title2))
                .foregroundStyle(Palette.skyInk)
                .frame(height: 30)
                .id(phase)
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    private var startButton: some View {
        Button {
            if isRunning { stopBreathing() } else { startBreathing() }
        } label: {
            Label(isRunning ? "Pause" : (phase == .done ? "Again · 1 minute" : "Start · 1 minute"),
                  systemImage: isRunning ? "pause.fill" : "play.fill")
                .font(.figtree(16, .heavy, relativeTo: .headline))
                .foregroundStyle(isRunning ? Palette.skyInk : .white)
                .padding(.horizontal, 28)
                .frame(height: 52)
                .background(isRunning ? Color(hex: 0xFFFEFB, opacity: 0.9) : Palette.blueButton, in: Capsule())
                .overlay {
                    if isRunning { Capsule().strokeBorder(Palette.blueRing, lineWidth: 1.5) }
                }
        }
        .buttonStyle(.pressable)
    }

    private func startBreathing() {
        noteCraving()
        player.stop()
        breathing = Task { @MainActor in
            for _ in 0..<6 {
                phase = .breatheIn
                withAnimation(.easeInOut(duration: 4)) { ringScale = 1; glow = 1 }
                guard await pause(4) else { return }
                phase = .hold
                guard await pause(1) else { return }
                phase = .breatheOut
                withAnimation(.easeInOut(duration: 5)) { ringScale = 0.72; glow = 0 }
                guard await pause(5) else { return }
            }
            phase = .done
            withAnimation(.easeInOut(duration: 1.2)) { ringScale = 0.86 }
            breathing = nil
        }
    }

    private func stopBreathing() {
        breathing?.cancel()
        breathing = nil
        phase = .idle
        withAnimation(.easeInOut(duration: 1.2)) { ringScale = 0.86; glow = 0 }
    }

    /// Waits, returning false if the exercise was stopped meanwhile.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    /// Counts this as a craving once, the first time the user does something here.
    private func noteCraving() {
        guard !loggedCraving else { return }
        loggedCraving = true
        store.logCraving()
    }

    // MARK: - Other things that help

    private func otherHelp(stage: TukStage) -> some View {
        VStack(spacing: 0) {
            if let note = encouragements.first(where: { $0.kind == .voice }) {
                voiceNoteRow(note)
                Divider().overlay(Palette.divider)
            } else if let photo = encouragements.first(where: { $0.kind == .photo }) {
                photoRow(photo)
                Divider().overlay(Palette.divider)
            } else {
                circleInviteRow
                Divider().overlay(Palette.divider)
            }
            talkRow(stage: stage)
        }
        .liftrCard()
    }

    private func voiceNoteRow(_ note: Encouragement) -> some View {
        let name = note.member?.name ?? "Someone"
        let isPlaying = player.isPlaying(note.fileURL)
        return HStack(spacing: 12) {
            InitialAvatar(name: name, color: note.member?.avatarColor ?? Palette.tan, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(name) left you a voice note")
                    .font(.figtree(14, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    WaveformBars(count: 28, progress: isPlaying ? player.progress : 0)
                    Text((note.duration ?? 0).minutesAndSeconds)
                        .font(.figtree(13, .bold, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            PlayButton(isPlaying: isPlaying) {
                noteCraving()
                stopBreathing()
                player.toggle(note.fileURL)
            }
            .accessibilityLabel(isPlaying ? "Pause voice note from \(name)" : "Play voice note from \(name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func photoRow(_ photo: Encouragement) -> some View {
        HStack(spacing: 12) {
            EncouragementPhoto(item: photo, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(photo.member?.name ?? "Someone") sent you a photo")
                    .font(.figtree(14, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                if let caption = photo.caption {
                    Text("“\(caption)”")
                        .font(.tuk(14))
                        .foregroundStyle(Palette.tukInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var circleInviteRow: some View {
        Button {
            dismiss()
            router.tab = .circle
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.brown)
                    .frame(width: 44, height: 44)
                    .background(Palette.tan, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hear from your circle")
                        .font(.figtree(16, .heavy, relativeTo: .headline))
                    Text("Save a voice note from someone who cares")
                        .font(.figtree(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func talkRow(stage: TukStage) -> some View {
        HStack(spacing: 12) {
            TukAvatar(stage: stage)
            VStack(alignment: .leading, spacing: 1) {
                Text("Talk to Tuk")
                    .font(.figtree(16, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text("Say it out loud, or type it")
                    .font(.figtree(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                roundButton("mic", label: "Talk to Tuk by voice") {
                    noteCraving()
                    router.openCoach(voice: true)
                }
                roundButton("bubble.left", label: "Chat with Tuk") {
                    noteCraving()
                    router.openCoach(voice: false)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.green)
                .frame(width: 44, height: 44)
                .background(Palette.greenSoft, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private var background: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0xD7E6F3), location: 0),
                .init(color: Color(hex: 0xE7EFF5), location: 0.4),
                .init(color: Palette.background, location: 0.76),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            SkyClouds()
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

/// The two soft clouds behind craving help.
private struct SkyClouds: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 390
            context.scaleBy(x: scale, y: scale)
            for offset in [CGSize(width: 0, height: 0), CGSize(width: 304, height: 90)] {
                var cloud = Path()
                cloud.move(to: CGPoint(x: 18, y: 262))
                cloud.addCurve(to: CGPoint(x: 14, y: 248), control1: CGPoint(x: 9, y: 262), control2: CGPoint(x: 7, y: 252))
                cloud.addCurve(to: CGPoint(x: 31, y: 241), control1: CGPoint(x: 14, y: 239), control2: CGPoint(x: 25, y: 235))
                cloud.addCurve(to: CGPoint(x: 54, y: 239), control1: CGPoint(x: 35, y: 232), control2: CGPoint(x: 49, y: 231))
                cloud.addCurve(to: CGPoint(x: 68, y: 250), control1: CGPoint(x: 62, y: 236), control2: CGPoint(x: 71, y: 242))
                cloud.addCurve(to: CGPoint(x: 68, y: 262), control1: CGPoint(x: 76, y: 251), control2: CGPoint(x: 77, y: 262))
                cloud.closeSubpath()
                let placed = cloud.applying(CGAffineTransform(translationX: offset.width, y: offset.height))
                context.fill(placed, with: .color(.white.opacity(0.85)))
                context.stroke(placed, with: .color(Color(hex: 0x2E2823, opacity: 0.5)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Round green play / pause button.
struct PlayButton: View {
    var isPlaying: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16))
                .foregroundStyle(Palette.onGreen)
                .frame(width: 44, height: 44)
                .background(Palette.green, in: Circle())
        }
        .buttonStyle(.pressable)
    }
}

/// A circle with someone's first initial.
struct InitialAvatar: View {
    var name: String
    var color: Color
    var size: CGFloat = 44

    var body: some View {
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(.figtree(size * 0.38, .heavy, relativeTo: .headline))
            .foregroundStyle(Palette.tanInk)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(Palette.outline, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}
