//
//  CheckInView.swift
//  LIFTR
//

import SwiftUI

/// Voice check-in with the ElevenLabs partner.
struct CheckInView: View {
    @Environment(CheckInPartner.self) private var partner

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                StatusOrb(status: partner.status)
                    .padding(.top, 24)

                Text(statusText)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let logged = partner.lastLogged {
                    Label(logged, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                if !partner.isConfigured {
                    SetupHint()
                } else {
                    Transcript(lines: partner.lines)
                }

                Spacer(minLength: 0)
                controls
                    .padding(.bottom)
            }
            .padding(.horizontal)
            .animation(.default, value: partner.lastLogged)
            .navigationTitle("Check-in")
        }
    }

    @ViewBuilder
    private var controls: some View {
        if partner.status.isLive {
            HStack(spacing: 16) {
                Button {
                    Task { await partner.toggleMute() }
                } label: {
                    Label(partner.isMuted ? "Unmute" : "Mute", systemImage: partner.isMuted ? "mic.slash.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task { await partner.end() }
                } label: {
                    Label("End", systemImage: "phone.down.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            Button {
                Task { await partner.start() }
            } label: {
                Label("Talk about your day", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!partner.isConfigured)
        }
    }

    private var statusText: String {
        switch partner.status {
        case .idle: "How did today go?"
        case .connecting: "Connecting…"
        case .listening: "Listening"
        case .thinking: "Thinking…"
        case .speaking: "Speaking"
        case .ended: "Talk again any time."
        case let .failed(message): message
        }
    }
}

private struct StatusOrb: View {
    var status: CheckInPartner.Status

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: 120, height: 120)
            .scaleEffect(status == .speaking ? 1.1 : 1)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: status == .speaking)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
    }

    private var color: Color {
        switch status {
        case .listening: .green
        case .speaking: .blue
        case .thinking, .connecting: .orange
        case .failed: .red
        case .idle, .ended: .gray
        }
    }

    private var symbol: String {
        switch status {
        case .listening: "ear"
        case .speaking: "waveform"
        case .thinking, .connecting: "ellipsis"
        case .failed: "exclamationmark.triangle"
        case .idle, .ended: "mic"
        }
    }
}

private struct Transcript: View {
    var lines: [CheckInPartner.Line]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .padding(10)
                            .background(line.fromUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: line.fromUser ? .trailing : .leading)
                            .id(line.id)
                    }
                }
            }
            .onChange(of: lines.count) {
                if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

private struct SetupHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice partner isn't set up yet")
                .font(.headline)
            Text("Copy Config/ElevenLabs.example.plist to LIFTR/ElevenLabs.plist and add your ElevenLabs agent ID. See docs/elevenlabs-agent.md.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
