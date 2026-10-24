//
//  CheckInPartner.swift
//  LIFTR
//

import Combine
import ElevenLabs
import Foundation

/// Runs a voice check-in with the ElevenLabs agent and saves what the user reports.
@Observable
final class CheckInPartner {
    enum Status: Equatable {
        case idle
        case connecting
        case listening
        case thinking
        case speaking
        case ended
        case failed(String)

        var isLive: Bool {
            switch self {
            case .connecting, .listening, .thinking, .speaking: true
            default: false
            }
        }
    }

    struct Line: Identifiable, Equatable {
        var id: String
        var fromUser: Bool
        var text: String
    }

    private(set) var status: Status = .idle
    private(set) var lines: [Line] = []
    private(set) var isMuted = false
    /// Set when the agent saves a check-in, so the UI can confirm it.
    private(set) var lastLogged: String?

    /// Bumped when the agent ID is saved in the app, so views re-check `isConfigured`.
    private var settingsRevision = 0

    var isConfigured: Bool {
        _ = settingsRevision
        return ElevenLabsSettings.load() != nil
    }

    /// Saves an agent ID pasted into the app. Returns false if it doesn't look like one.
    @discardableResult
    func saveAgentID(_ raw: String) -> Bool {
        guard let id = ElevenLabsSettings.normalizedAgentID(raw) else { return false }
        UserDefaults.standard.set(id, forKey: ElevenLabsSettings.savedAgentIDKey)
        settingsRevision += 1
        return true
    }

    private let store: CheckInStore
    @ObservationIgnored private var conversation: Conversation?
    @ObservationIgnored private var observers: [Task<Void, Never>] = []
    @ObservationIgnored private var handledToolCalls: Set<String> = []
    /// Bumped by every start and end, so a connection that finishes after the user
    /// already tapped End (or started again) can tell it's stale and hang up.
    @ObservationIgnored private var attempt = 0

    init(store: CheckInStore) {
        self.store = store
    }

    /// Why the user started the call. Sent to the agent as {{call_reason}} and picks the opening line.
    enum CallReason: String {
        case checkIn = "check_in"
        case craving
    }

    func start(reason: CallReason = .checkIn) async {
        guard !status.isLive else { return }
        guard let settings = ElevenLabsSettings.load() else {
            status = .failed("Add your agent ID to ElevenLabs.plist to start talking.")
            return
        }

        lines = []
        lastLogged = nil
        handledToolCalls = []
        status = .connecting
        store.refresh()
        attempt += 1
        let thisAttempt = attempt

        let config = ConversationConfig(dynamicVariables: dynamicVariables(reason: reason))
        do {
            let conversation: Conversation
            if let tokenURL = settings.conversationTokenURL {
                conversation = try await ElevenLabs.startConversation(
                    tokenProvider: { try await CheckInPartner.fetchToken(from: tokenURL) },
                    config: config
                )
            } else {
                conversation = try await ElevenLabs.startConversation(agentId: settings.agentID, config: config)
            }
            guard thisAttempt == attempt else {
                await conversation.endConversation()
                return
            }
            self.conversation = conversation
            observe(conversation)
        } catch {
            if thisAttempt == attempt { status = .failed(error.localizedDescription) }
        }
    }

    func end() async {
        attempt += 1
        await conversation?.endConversation()
        stopObserving()
        conversation = nil
        if status.isLive { status = .ended }
    }

    func toggleMute() async {
        try? await conversation?.toggleMute()
    }

    // MARK: - Conversation events

    private func observe(_ conversation: Conversation) {
        stopObserving()
        observers = [
            Task { [weak self] in
                for await state in conversation.$state.values {
                    self?.update(state: state, agentState: conversation.agentState)
                }
            },
            Task { [weak self] in
                for await agentState in conversation.$agentState.values {
                    self?.update(state: conversation.state, agentState: agentState)
                }
            },
            Task { [weak self] in
                for await messages in conversation.$messages.values {
                    self?.lines = messages.compactMap { message in
                        let fromUser = message.role == .user
                        let text = fromUser ? message.content : CheckInPartner.removingAudioTags(message.content)
                        guard !text.isEmpty else { return nil }
                        return Line(id: message.id, fromUser: fromUser, text: text)
                    }
                }
            },
            Task { [weak self] in
                for await muted in conversation.$isMuted.values {
                    self?.isMuted = muted
                }
            },
            Task { [weak self] in
                for await calls in conversation.$pendingToolCalls.values {
                    for call in calls {
                        Task { await self?.handle(call, in: conversation) }
                    }
                }
            },
        ]
    }

    private func stopObserving() {
        observers.forEach { $0.cancel() }
        observers = []
    }

    private func update(state: ConversationState, agentState: ElevenLabs.AgentState) {
        switch state {
        case .idle, .connecting:
            status = .connecting
        case .active:
            switch agentState {
            case .listening: status = .listening
            case .thinking: status = .thinking
            case .speaking: status = .speaking
            }
        case .ended:
            status = .ended
            stopObserving()
        case let .error(error):
            status = .failed(error.localizedDescription)
            stopObserving()
        }
    }

    private func handle(_ call: ClientToolCallEvent, in conversation: Conversation) async {
        guard handledToolCalls.insert(call.toolCallId).inserted else { return }

        let parameters = (try? call.getParameters()) ?? [:]
        let outcome = PartnerTools.run(name: call.toolName, parameters: parameters, store: store)
        if let summary = outcome.loggedSummary {
            lastLogged = summary
        }

        if call.expectsResponse {
            try? await conversation.sendToolResult(for: call.toolCallId, result: outcome.json, isError: outcome.isError)
        } else {
            conversation.markToolCallCompleted(call.toolCallId)
        }
    }

    // MARK: - Setup

    /// Values the agent's prompt can reference as {{variable_name}}. Every variable used in
    /// the agent's prompt or first message must be sent here, or the conversation won't start.
    private func dynamicVariables(reason: CallReason) -> [String: String] {
        let progress = store.progress
        let opening = switch reason {
        case .checkIn:
            "Hey! Good to hear from you. \(Pet.name) is feeling \(progress.petMood.rawValue) today. How did your day go?"
        case .craving:
            "I'm here. Cravings feel huge, but they usually pass within a few minutes. Let's ride this one out together. What's going on right now?"
        }
        return [
            "call_reason": reason.rawValue,
            "opening_line": opening,
            "sober_streak_days": String(progress.currentStreak),
            "longest_streak_days": String(progress.longestStreak),
            "logged_today": progress.loggedToday ? "yes" : "no",
            "cigarettes_today": progress.cigarettesToday.map(String.init) ?? "not logged yet",
            "liftr_score": String(progress.score),
            "pet_name": Pet.name,
            "pet_mood": progress.petMood.rawValue,
        ]
    }

    /// Drops the agent's expressive audio tags, like "[happy]" or "[laughs]", from its text.
    /// Also drops a tag still being streamed in, so "[hap" doesn't flash on screen.
    nonisolated static func removingAudioTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[ \t]*\[[A-Za-z][A-Za-z '\-]*(\]|$)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Asks our own backend for a conversation token for a private agent.
    nonisolated private static func fetchToken(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard
            (response as? HTTPURLResponse)?.statusCode == 200,
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = body["token"] as? String
        else { throw URLError(.badServerResponse) }
        return token
    }
}
