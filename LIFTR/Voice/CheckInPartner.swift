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
    /// The call's transcript. Tuk's latest reply shows a sentence at a time, as it's spoken.
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
    /// Every line as the agent sent it, before Tuk's latest reply is cut down to what's been said.
    @ObservationIgnored private var fullLines: [Line] = []
    /// Tuk's reply being read out, how many of its sentences are on screen,
    /// and how long Tuk has been speaking it.
    @ObservationIgnored private var spokenLineID: String?
    @ObservationIgnored private var shownSentences = 0
    @ObservationIgnored private var speakingTime: Duration = .zero
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
        fullLines = []
        spokenLineID = nil
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
                    self?.update(lines: messages.compactMap { message in
                        let fromUser = message.role == .user
                        let text = fromUser ? message.content : CheckInPartner.removingAudioTags(message.content)
                        guard !text.isEmpty else { return nil }
                        return Line(id: message.id, fromUser: fromUser, text: text)
                    })
                }
            },
            Task { [weak self] in
                let tick = Duration.milliseconds(100)
                while !Task.isCancelled {
                    try? await Task.sleep(for: tick)
                    self?.advanceSpokenLine(by: tick)
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
        showWholeReply()
    }

    // MARK: - Captions

    /// Roughly how fast Tuk talks, plus a short breath between sentences.
    private static let charactersPerSecond = 14.0
    private static let pauseBetweenSentences = Duration.milliseconds(250)

    private func update(lines newLines: [Line]) {
        fullLines = newLines
        // A new reply from Tuk starts with just its first sentence.
        if let last = newLines.last, !last.fromUser, last.id != spokenLineID {
            spokenLineID = last.id
            shownSentences = 1
            speakingTime = .zero
        }
        refreshLines()
    }

    /// Shows the next sentence once Tuk has been speaking long enough to have said the ones on screen.
    private func advanceSpokenLine(by tick: Duration) {
        guard status == .speaking, shownSentences != .max,
              let line = fullLines.first(where: { $0.id == spokenLineID }) else { return }
        speakingTime += tick
        let sentences = Self.sentences(in: line.text)
        guard shownSentences < sentences.count else { return }
        let saidSoFar = sentences.prefix(shownSentences).reduce(Duration.zero) { total, sentence in
            total + .seconds(Double(sentence.count) / Self.charactersPerSecond) + Self.pauseBetweenSentences
        }
        if speakingTime >= saidSoFar {
            shownSentences += 1
            refreshLines()
        }
    }

    /// Once Tuk stops talking, the rest of the reply goes on screen so the transcript is complete.
    private func showWholeReply() {
        guard shownSentences != .max else { return }
        shownSentences = .max
        refreshLines()
    }

    private func refreshLines() {
        lines = fullLines.map { line in
            guard line.id == spokenLineID else { return line }
            let shown = Self.sentences(in: line.text).prefix(shownSentences).joined()
            return Line(id: line.id, fromUser: line.fromUser, text: shown.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Splits text after each ".", "!", "?" or "…" that's followed by a space, keeping the spaces.
    nonisolated static func sentences(in text: String) -> [Substring] {
        var sentences: [Substring] = []
        var start = text.startIndex
        while let end = text.range(of: #"[.!?…]+["”’)]*\s+"#, options: .regularExpression, range: start..<text.endIndex) {
            sentences.append(text[start..<end.upperBound])
            start = end.upperBound
        }
        if start < text.endIndex { sentences.append(text[start...]) }
        return sentences
    }

    private func update(state: ConversationState, agentState: ElevenLabs.AgentState) {
        switch state {
        case .idle, .connecting:
            status = .connecting
        case .active:
            switch agentState {
            case .listening:
                if status == .speaking { showWholeReply() }
                status = .listening
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
            "tuk_stage": progress.stage.title,
            // Older agent prompts call Tuk "the pet"; these keep their greeting working.
            "pet_name": TukStage.name,
            "pet_mood": progress.stage.mood,
            "opening_message": openingMessage(),
        ]
    }

    /// What Tuk says first, from what's already logged today. The agent's first message
    /// in the ElevenLabs dashboard should be just {{opening_message}}.
    private func openingMessage() -> String {
        let progress = store.progress
        guard progress.firstDay != nil else {
            return "Hi, I'm Tuk. I'm here to help you cut down, one day at a time. How's today going?"
        }
        let streak = progress.currentStreak
        guard progress.loggedToday else {
            let streakLine = streak > 0 ? " You're on a \(streak)-day streak." : ""
            return "Hey, it's Tuk. Nothing logged yet today.\(streakLine) How's it going so far?"
        }

        let counts: [(Product, Int)] = [
            (.cigarette, progress.cigarettesToday ?? 0),
            (.vape, progress.vapesToday),
            (.pouch, progress.pouchesToday),
        ]
        let logged = counts.filter { $0.1 > 0 }.map { "\($0.1) \($0.0.noun($0.1))" }
        guard !logged.isEmpty else {
            let streakLine = streak > 1 ? " That's \(streak) days in a row." : ""
            return "Hey, it's Tuk. No nicotine today.\(streakLine) I'm proud of you. How are you feeling?"
        }

        let list = logged.count == 1
            ? logged[0]
            : logged.dropLast().joined(separator: ", ") + " and " + logged[logged.count - 1]
        var message = "Hey, it's Tuk. So far today you've logged \(list)."
        if let usual = store.patterns.usualCigarettesByNow.map({ Int($0.rounded()) }) {
            let cigarettes = progress.cigarettesToday ?? 0
            if cigarettes < usual {
                message += " That's fewer cigarettes than you'd usually have by now. Nice."
            } else if cigarettes > usual {
                message += " A bit more than usual, and that's okay. Some days are harder."
            }
        }
        return message + " How's it going?"
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
