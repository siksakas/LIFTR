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

        // Cigarettes tapped on the watch that the partner hasn't asked about yet.
        // Marked as talked about once the call connects.
        let quickLogs = store.cigarettesNotTalkedAbout()
        let config = ConversationConfig(dynamicVariables: dynamicVariables(quickLogs: quickLogs, now: .now))
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
            store.markTalkedAbout(quickLogs)
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
    private func dynamicVariables(quickLogs: [CigaretteEvent], now: Date) -> [String: String] {
        let progress = store.progress
        return [
            "sober_streak_days": String(progress.currentStreak),
            "longest_streak_days": String(progress.longestStreak),
            "logged_today": progress.loggedToday ? "yes" : "no",
            "cigarettes_today": progress.cigarettesToday.map(String.init) ?? "not logged yet",
            "liftr_score": String(progress.score),
            "pet_name": Pet.name,
            "pet_mood": progress.petMood.rawValue,
            "watch_cigarettes_since_last_talk": String(quickLogs.count),
            "watch_cigarette_times": Self.describeTimes(of: quickLogs, now: now),
        ]
    }

    /// "today at 9:14 AM, today at 1:40 PM", or "none". Spoken by the agent, so plain words.
    private static func describeTimes(of logs: [CigaretteEvent], now: Date, calendar: Calendar = .current) -> String {
        guard !logs.isEmpty else { return "none" }
        let time = DateFormatter()
        time.timeStyle = .short
        time.dateStyle = .none
        let weekday = DateFormatter()
        weekday.setLocalizedDateFormatFromTemplate("EEEE")
        // Long lists are tiring to hear; the count variable still has the full number.
        let listed = logs.suffix(8)
        let earlier = logs.count - listed.count
        let times = listed.map { log in
            let day: String
            if calendar.isDate(log.smokedAt, inSameDayAs: now) {
                day = "today"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                      calendar.isDate(log.smokedAt, inSameDayAs: yesterday) {
                day = "yesterday"
            } else {
                day = "on " + weekday.string(from: log.smokedAt)
            }
            return "\(day) at \(time.string(from: log.smokedAt))"
        }
        let prefix = earlier > 0 ? ["\(earlier) earlier"] : []
        return (prefix + times).joined(separator: ", ")
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
