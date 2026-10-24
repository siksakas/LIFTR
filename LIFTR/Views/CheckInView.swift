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

/// Shows only the most recent line of the conversation. When a new line
/// arrives the old one drifts up and fades out while the new one rises in.
private struct Transcript: View {
    var lines: [CheckInPartner.Line]

    private var latest: (line: CheckInPartner.Line, text: String)? {
        for line in lines.reversed() {
            let text = Self.displayText(line.text)
            if !text.isEmpty { return (line, text) }
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let latest {
                Text(latest.text)
                    .font(.title3)
                    .multilineTextAlignment(latest.line.fromUser ? .trailing : .leading)
                    .padding(14)
                    .background(latest.line.fromUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, alignment: latest.line.fromUser ? .trailing : .leading)
                    .id(latest.line.id)
                    .transition(.asymmetric(
                        insertion: .offset(y: 40).combined(with: .opacity),
                        removal: .offset(y: -60).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .animation(.easeInOut(duration: 0.45), value: latest?.line.id)
    }

    /// Strips ElevenLabs v3 audio tags such as `[happy]` or `[gentle]` and
    /// tidies the whitespace they leave behind.
    static func displayText(_ text: String) -> String {
        text.replacing(/\[[^\]]*\]/, with: "")
            .replacing(/\s+([,.!?;:])/, with: { $0.output.1 })
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SetupHint: View {
    @Environment(CheckInPartner.self) private var partner
    @State private var agentID = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice partner isn't set up yet")
                .font(.headline)
            Text("Paste your ElevenLabs agent ID below, or add it to LIFTR/ElevenLabs.plist. See docs/elevenlabs-agent.md.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("agent_…", text: $agentID)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(save)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(agentID.isEmpty)
            }
            if invalid {
                Text("That doesn't look like an agent ID. It starts with agent_.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func save() {
        invalid = !partner.saveAgentID(agentID)
    }
}
