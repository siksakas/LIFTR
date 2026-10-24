//
//  CoachView.swift
//  LIFTR
//

import SwiftUI

/// One place to talk to Liftr: a voice check-in with the ElevenLabs partner, or a text chat with
/// the AI coach. The text coach runs on an open-weights model on DigitalOcean, reached through the
/// backend, and reads the user's trends from Snowflake. Voice calls land in the same thread, so the
/// text coach knows what was said, and their transcripts are synced to Snowflake.
struct CoachView: View {
    @Environment(CheckInStore.self) private var store
    @Environment(CheckInPartner.self) private var partner
    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isWaiting = false
    @State private var errorMessage: String?
    /// Last voice line already copied into `messages`, so a call is only added once.
    @State private var lastFoldedLineID: String?
    /// Bumped when a backend URL is saved in the app, so the view re-checks the settings.
    @State private var settingsRevision = 0

    private static let quickPrompts = [
        "I'm craving right now",
        "How am I doing?",
        "What are my patterns?",
        "Help me plan tomorrow",
    ]

    private var settings: BackendSettings? {
        _ = settingsRevision
        return BackendSettings.load()
    }

    /// Lines of the call in progress. Once it ends they're copied into `messages`.
    private var liveLines: [CheckInPartner.Line] {
        partner.status.isLive ? partner.lines : []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                if partner.status.isLive {
                    callBar
                } else {
                    if settings != nil { quickPromptRow }
                    inputBar
                }
            }
            .navigationTitle("Coach")
            .animation(.default, value: partner.status.isLive)
            .onChange(of: partner.status.isLive) { foldInFinishedCall() }
            .onAppear(perform: foldInFinishedCall)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if settings == nil {
                        BackendSetupCard {
                            settingsRevision += 1
                            store.syncPending()
                        }
                    }
                    if !partner.isConfigured {
                        VoiceSetupCard()
                    }
                    if messages.isEmpty && liveLines.isEmpty {
                        Text("Talk through your day by voice, or type to ask for help with a craving or about your progress. The coach can see your check-ins.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(messages) { message in
                        Bubble(fromUser: message.fromUser, text: message.text, viaVoice: message.viaVoice)
                    }
                    ForEach(liveLines) { line in
                        Bubble(fromUser: line.fromUser, text: line.text, viaVoice: true)
                    }
                    if isWaiting {
                        ProgressView()
                            .padding(.vertical, 4)
                    }
                    if !partner.status.isLive, let logged = partner.lastLogged {
                        Label(logged, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if case let .failed(message) = partner.status {
                        Text("Voice check-in stopped: \(message)")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let syncError = store.syncError {
                        Label("Check-ins aren't syncing: \(syncError)", systemImage: "exclamationmark.icloud")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding()
            }
            .onChange(of: messages.count + liveLines.count) {
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private static let bottomID = "bottom"

    /// Shown instead of the text box while a voice check-in is live.
    private var callBar: some View {
        HStack(spacing: 12) {
            StatusOrb(status: partner.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(callStatusText)
                    .font(.headline)
                if let logged = partner.lastLogged {
                    Label(logged, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await partner.toggleMute() }
            } label: {
                Image(systemName: partner.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(partner.isMuted ? "Unmute" : "Mute")
            Button(role: .destructive) {
                Task { await partner.end() }
            } label: {
                Image(systemName: "phone.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("End call")
        }
        .padding()
        .background(.bar)
        .animation(.default, value: partner.lastLogged)
    }

    private var callStatusText: String {
        switch partner.status {
        case .connecting: "Connecting…"
        case .listening: "Listening"
        case .thinking: "Thinking…"
        case .speaking: "Speaking"
        case .idle, .ended, .failed: ""
        }
    }

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickPrompts, id: \.self) { prompt in
                    Button(prompt) { send(prompt) }
                        .buttonStyle(.bordered)
                        .disabled(isWaiting)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }

    private var inputBar: some View {
        HStack {
            Button {
                startCall()
            } label: {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
            }
            .disabled(!partner.isConfigured)
            .accessibilityLabel("Talk about your day")

            TextField(settings == nil ? "Connect the backend to chat" : "Message your coach", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(settings == nil)
                .onSubmit { send(draft) }
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(settings == nil || isWaiting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding([.horizontal, .bottom])
    }

    private func startCall() {
        foldInFinishedCall()
        errorMessage = nil
        Task { await partner.start() }
    }

    /// Copies a finished call's lines into the thread, so they stay after the next call starts
    /// and the text coach can read them.
    private func foldInFinishedCall() {
        guard !partner.status.isLive, let last = partner.lines.last, last.id != lastFoldedLineID else { return }
        lastFoldedLineID = last.id
        messages += partner.lines.map { CoachMessage(fromUser: $0.fromUser, text: $0.text, viaVoice: true) }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWaiting, let settings else { return }

        messages.append(CoachMessage(fromUser: true, text: trimmed))
        draft = ""
        errorMessage = nil
        isWaiting = true
        let history = messages
        let progress = store.progress

        Task {
            defer { isWaiting = false }
            do {
                let reply = try await BackendClient(settings: settings).coachReply(messages: history, progress: progress)
                messages.append(CoachMessage(fromUser: false, text: reply))
            } catch {
                errorMessage = "The coach couldn't answer: \(error.localizedDescription)"
            }
        }
    }
}

private struct Bubble: View {
    var fromUser: Bool
    var text: String
    var viaVoice: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if viaVoice {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Said by voice")
            }
            Text(text)
        }
        .padding(10)
        .background(fromUser ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: fromUser ? .trailing : .leading)
    }
}

private struct StatusOrb: View {
    var status: CheckInPartner.Status

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: 44, height: 44)
            .scaleEffect(status == .speaking ? 1.1 : 1)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: status == .speaking)
            .overlay {
                Image(systemName: symbol)
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

private struct BackendSetupCard: View {
    var onSave: () -> Void
    @State private var address = "http://localhost:8080"
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach isn't connected yet")
                .font(.headline)
            Text("Start the backend (see backend/README.md) and enter its address. In the simulator on the same Mac, that's http://localhost:8080. You can also add it to LIFTR/Backend.plist.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("https://…", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(save)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(address.isEmpty)
            }
            if invalid {
                Text("That doesn't look like a web address. It starts with http:// or https://.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func save() {
        guard let url = BackendSettings.normalizedURL(address) else {
            invalid = true
            return
        }
        invalid = false
        UserDefaults.standard.set(url.absoluteString, forKey: BackendSettings.savedURLKey)
        onSave()
    }
}

private struct VoiceSetupCard: View {
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
