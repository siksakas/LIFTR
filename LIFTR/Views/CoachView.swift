//
//  CoachView.swift
//  LIFTR
//

import SwiftUI

/// Text chat with the AI coach. The coach runs on an open-weights model on DigitalOcean,
/// reached through the backend, and reads the user's trends from Snowflake.
struct CoachView: View {
    @Environment(CheckInStore.self) private var store
    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isWaiting = false
    @State private var errorMessage: String?
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if settings == nil {
                    BackendSetupCard {
                        settingsRevision += 1
                        store.syncPending()
                    }
                    .padding()
                    Spacer()
                } else {
                    conversation
                    quickPromptRow
                    inputBar
                }
            }
            .navigationTitle("Coach")
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        Text("Ask for help with a craving, or about your progress. The coach can see your check-ins.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(messages) { message in
                        Text(message.text)
                            .padding(10)
                            .background(message.fromUser ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
                            .id(message.id)
                    }
                    if isWaiting {
                        ProgressView()
                            .padding(.vertical, 4)
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
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
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
            TextField("Message your coach", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { send(draft) }
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(isWaiting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding([.horizontal, .bottom])
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
