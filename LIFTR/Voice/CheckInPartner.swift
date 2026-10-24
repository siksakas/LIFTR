//
//  CheckInPartner.swift
//  LIFTR
//

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

    var isConfigured: Bool { ElevenLabsSettings.load() != nil }

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

    func start() async {
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

        let config = ConversationConfig(dynamicVariables: dynamicVariables())
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
                    self?.lines = messages
                        .filter { !$0.content.isEmpty }
                        .map { Line(id: $0.id, fromUser: $0.role == .user, text: $0.content) }
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
    private func dynamicVariables() -> [String: String] {
        let progress = store.progress
        return [
            "sober_streak_days": String(progress.currentStreak),
            "longest_streak_days": String(progress.longestStreak),
            "logged_today": progress.loggedToday ? "yes" : "no",
            "cigarettes_today": progress.cigarettesToday.map(String.init) ?? "not logged yet",
            "liftr_score": String(progress.score),
            "pet_name": Pet.name,
            "pet_mood": progress.petMood.rawValue,
        ]
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
