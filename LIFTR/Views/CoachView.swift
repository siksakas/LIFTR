//
//  CoachView.swift
//  LIFTR
//

import SwiftUI

/// Coach Tuk: type, or talk out loud with the ElevenLabs voice partner. Learns only from your logs.
struct CoachView: View {
    enum Mode { case text, voice }

    /// Typing is switched off for now, so Coach is voice only. Set to true to bring the Text tab back.
    static let allowsTyping = false

    @Environment(CheckInStore.self) private var store
    @Environment(CheckInPartner.self) private var partner
    @Environment(Reminders.self) private var reminders
    @Environment(AppRouter.self) private var router

    @State private var thread = CoachThread()
    @State private var mode = CoachView.allowsTyping ? Mode.text : Mode.voice
    @State private var draft = ""
    /// Lines from the current or last voice call that aren't in the thread yet.
    @State private var showsCallLines = false
    /// Set when a voice call ends, to show where the day stands.
    @State private var showsDayCard = false
    @FocusState private var isTyping: Bool

    /// Bumped when a backend address is saved in the app, so the view re-checks the settings.
    @State private var settingsRevision = 0

    private var backend: BackendSettings? {
        _ = settingsRevision
        return BackendSettings.load()
    }

    var body: some View {
        VStack(spacing: 0) {
            if Self.allowsTyping { header }
            conversation
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if mode == .voice, !partner.isConfigured {
                    AgentSetupCard()
                }
                if mode == .text, backend == nil {
                    BackendSetupCard {
                        settingsRevision += 1
                        store.syncPending()
                    }
                }
                if mode == .text { textInput } else { voiceButton }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, isTyping ? 8 : LiftrTabBar.clearance + 2)
            .background(Palette.background)
        }
        .onAppear {
            thread.start(patterns: store.patterns, reminders: reminders)
            handleRouterRequests()
        }
        .onChange(of: router.coachStartsVoice) { handleRouterRequests() }
        .onChange(of: router.coachPrefersText) { handleRouterRequests() }
        .onChange(of: partner.status) {
            // Fold a finished call into the thread so typing afterwards keeps the order.
            if !partner.status.isLive, case .ended = partner.status {
                foldCallIntoThread()
                store.refresh()
                showsDayCard = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                segment("Text", isOn: mode == .text) { switchMode(.text) }
                segment("Voice", isOn: mode == .voice) { switchMode(.voice) }
            }
            .padding(3)
            .background(Palette.sandDeep, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Type or talk")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .padding(.top, 4)
    }

    private func segment(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.figtree(13, .heavy, relativeTo: .footnote))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background {
                    if isOn {
                        Capsule().fill(Palette.card).shadow(color: Palette.ink.opacity(0.18), radius: 1.5, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func switchMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        withAnimation(.easeOut(duration: 0.2)) { mode = newMode }
        if newMode == .text, partner.status.isLive {
            Task { await partner.end() }
        }
        if newMode == .voice { isTyping = false }
    }

    private func handleRouterRequests() {
        if router.coachStartsVoice {
            router.coachStartsVoice = false
            switchMode(.voice)
            if partner.isConfigured, !partner.status.isLive { startCall() }
        }
        if router.coachPrefersText {
            router.coachPrefersText = false
            if Self.allowsTyping {
                switchMode(.text)
                isTyping = true
            }
        }
    }

    // MARK: - Conversation

    private var callItems: [CoachThread.Item] {
        guard showsCallLines else { return [] }
        var items = partner.lines.map { line in
            CoachThread.Item(id: "call-\(line.id)", kind: line.fromUser ? .voice(line.text) : .tuk(line.text, nil))
        }
        if let logged = partner.lastLogged {
            items.append(CoachThread.Item(id: "call-logged", kind: .note("✓ \(logged)")))
        }
        if case let .failed(message) = partner.status {
            items.append(CoachThread.Item(id: "call-failed", kind: .note(message)))
        }
        return items
    }

    /// The last sentence of what Tuk said, with any cards from that same turn.
    private struct TukTurn: Equatable {
        var text: String
        var attachments: [CoachThread.Attachment]
    }

    private var latestTuk: TukTurn? {
        let items = thread.items + callItems
        guard let last = items.lastIndex(where: \.isFromTuk) else { return nil }
        // Tuk's turn runs back to the user's last message, so a card he showed just before
        // his latest line (like the week's toughest window) stays on screen with it.
        let turnStart = items[..<last].lastIndex(where: \.isFromUser).map { $0 + 1 } ?? 0
        let attachments = items[turnStart...last].compactMap { item -> CoachThread.Attachment? in
            guard case let .tuk(_, attachment) = item.kind else { return nil }
            return attachment
        }
        guard case let .tuk(text, _) = items[last].kind else { return nil }
        return TukTurn(text: text.lastSentence, attachments: attachments)
    }

    private var latestUser: CoachThread.Item? {
        (thread.items + callItems).last(where: \.isFromUser)
    }

    /// A note like "✓ Logged" or an error, when it's the newest thing in the conversation.
    private var trailingNote: String? {
        guard !showsDayCard, case let .note(text) = (thread.items + callItems).last?.kind else { return nil }
        return text
    }

    private var tukIsComposing: Bool {
        thread.isTyping || partner.status == .thinking
    }

    private var conversation: some View {
        let stage = max(store.progress.stage, .cuttingDown)
        return GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            ZStack {
                                if partner.status == .speaking || partner.status == .listening {
                                    PulseRings(color: partner.status == .speaking ? Palette.greenPulse : Palette.blueRing, size: 168)
                                        .frame(width: 168, height: 168)
                                }
                                TukAvatar(stage: stage, size: 168, lineWidth: 2)
                            }
                            .frame(width: 168, height: 168)
                            Text("Coach Tuk")
                                .font(.figtree(22, .heavy, relativeTo: .title3))
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(.bottom, 6)

                        if tukIsComposing {
                            TypingDots().transition(.opacity)
                        } else if let latestTuk {
                            VStack(spacing: 12) {
                                Text(latestTuk.text)
                                    .font(.tuk(17))
                                    .foregroundStyle(Palette.tukInk)
                                    .lineSpacing(3)
                                    .multilineTextAlignment(.center)
                                ForEach(Array(latestTuk.attachments.enumerated()), id: \.offset) { _, attachment in
                                    AttachmentView(attachment: attachment) { router.showingCravingHelp = true }
                                        .frame(maxWidth: 300)
                                }
                            }
                            .id(latestTuk.text)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                        }

                        if let latestUser {
                            UserLine(item: latestUser)
                                .id(latestUser.id)
                                .transition(.opacity.combined(with: .offset(y: 8)))
                        }

                        if !thread.suggestions.isEmpty, !thread.isTyping {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { suggestionChips }
                                VStack(spacing: 8) { suggestionChips }
                            }
                            .transition(.opacity)
                        }

                        if showsDayCard {
                            DayCard()
                                .transition(.opacity.combined(with: .offset(y: 10)))
                        }

                        if let trailingNote {
                            Text(trailingNote)
                                .font(.figtree(13, .semibold, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSecondary)
                                .multilineTextAlignment(.center)
                        }
                        if let syncError = store.syncError {
                            Label("Check-ins aren't syncing: \(syncError)", systemImage: "exclamationmark.icloud")
                                .font(.figtree(13, .semibold, relativeTo: .footnote))
                                .foregroundStyle(Palette.tanInk)
                                .multilineTextAlignment(.center)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .animation(.easeOut(duration: 0.3), value: latestTuk)
                    .animation(.easeOut(duration: 0.3), value: latestUser)
                    .animation(.easeOut(duration: 0.3), value: tukIsComposing)
                    .animation(.easeOut(duration: 0.3), value: thread.suggestions)
                    .animation(.spring(duration: 0.45), value: showsDayCard)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                // When the keyboard leaves less room than the stage needs, keep the newest lines in view.
                .onChange(of: latestTuk) { scrollToBottom(proxy) }
                .onChange(of: latestUser) { scrollToBottom(proxy) }
                .onChange(of: isTyping) { scrollToBottom(proxy) }
                .onChange(of: showsDayCard) { scrollToBottom(proxy) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var suggestionChips: some View {
        ForEach(thread.suggestions, id: \.self) { suggestion in
            Button(suggestion.rawValue) { pick(suggestion) }
                .font(.figtree(14, .heavy, relativeTo: .subheadline))
                .foregroundStyle(Palette.greenDark)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.green, lineWidth: 1.5))
                .buttonStyle(.pressable)
        }
    }

    // MARK: - Typing

    private var textInput: some View {
        HStack(spacing: 8) {
            TextField("Message Tuk…", text: $draft)
                .font(.figtree(15, relativeTo: .body))
                .foregroundStyle(Palette.ink)
                .focused($isTyping)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color(hex: 0xDDD3C2), lineWidth: 1))
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.onGreen)
                    .frame(width: 52, height: 52)
                    .background(Palette.green, in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thread.isTyping)
            .accessibilityLabel("Send")
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thread.isTyping else { return }
        draft = ""
        foldCallIntoThread()
        thread.clearSuggestions()
        thread.append(.me(text))

        guard let backend else {
            thread.append(.note("Typed replies need the LIFTR backend. Enter its address below, or switch to Voice."))
            return
        }
        let history = thread.chatHistory
        let progress = store.progress
        Task {
            thread.setTyping(true)
            do {
                let reply = try await BackendClient(settings: backend).coachReply(messages: history, progress: progress)
                thread.setTyping(false)
                thread.append(.tuk(reply, nil))
            } catch {
                thread.setTyping(false)
                thread.append(.note("Couldn't reach the coach: \(error.localizedDescription)"))
            }
        }
    }

    private func pick(_ suggestion: CoachThread.Suggestion) {
        thread.clearSuggestions()
        switch suggestion {
        case .planIt:
            thread.append(.me("Yes, plan it."))
            let window = thread.offeredWindow ?? .afternoon
            Task {
                await reminders.setBreather(true, window: window)
                if reminders.breatherEnabled {
                    let time = Reminders.timeText(window.breatherTime)
                    await thread.reply(.tuk("Done. Weekdays at \(time) I'll check in. A 3-minute walk, or tea with me. You pick.", .plan("Weekdays · \(time)")))
                } else {
                    await thread.reply(.tuk("I can't send check-ins while notifications are off. You can allow them in Settings, then try again from the bell on Home.", nil))
                }
            }
        case .otherIdeas:
            thread.append(.me("What else could I try?"))
            Task { await thread.reply(.tuk("Step outside. Cold water. A quick text to someone you like. Or one minute of breathing with me.", .breathe)) }
        case .notToday:
            thread.append(.me("Not today."))
            Task { await thread.reply(.tuk("That's okay. I'm here whenever you want to talk.", nil)) }
        }
    }

    // MARK: - Voice

    private var voiceButton: some View {
        let isLive = partner.status.isLive
        return HStack(spacing: 10) {
            if isLive {
                Button {
                    Task { await partner.toggleMute() }
                } label: {
                    Image(systemName: partner.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.green)
                        .frame(width: 52, height: 52)
                        .background(Palette.greenSoft, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(partner.isMuted ? "Unmute" : "Mute")
            }
            ZStack {
                if partner.status == .listening {
                    PulseRings(color: Palette.greenPulse, size: 52, cornerRadius: 26)
                }
                Button {
                    if isLive { Task { await partner.end() } } else { startCall() }
                } label: {
                    Label(voiceLabel, systemImage: isLive ? "phone.down.fill" : "mic")
                        .font(.figtree(15, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.onGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Palette.green, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(!partner.isConfigured)
                .opacity(partner.isConfigured ? 1 : 0.5)
            }
            .frame(height: 52)
        }
        .animation(.easeOut(duration: 0.2), value: isLive)
    }

    private var voiceLabel: String {
        switch partner.status {
        case .connecting: "Connecting… tap to end"
        case .listening: "Listening… tap to end"
        case .thinking: "Tuk is thinking…"
        case .speaking: "Tuk is talking…"
        case .idle, .ended, .failed: "Tap to talk to Tuk"
        }
    }

    private func startCall() {
        foldCallIntoThread()
        thread.clearSuggestions()
        showsDayCard = false
        showsCallLines = true
        Task { await partner.start() }
    }

    /// Moves the last call's transcript into the thread. A new call clears `partner.lines`.
    private func foldCallIntoThread() {
        guard showsCallLines, !partner.status.isLive else { return }
        thread.append(callItems)
        showsCallLines = false
    }
}

// MARK: - Lines

/// The last sentence the user said or typed, under Tuk's.
private struct UserLine: View {
    var item: CoachThread.Item

    var body: some View {
        switch item.kind {
        case let .me(text):
            Text(text.lastSentence)
                .font(.figtree(16, relativeTo: .body))
                .foregroundStyle(Palette.greenInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.greenBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel("You: \(text.lastSentence)")
        case let .voice(text):
            VStack(spacing: 7) {
                WaveformBars(count: 24, idle: Color(hex: 0x5E7C62))
                Text("“\(text.lastSentence)”")
                    .font(.figtree(15, relativeTo: .subheadline))
                    .italic()
                    .foregroundStyle(Palette.greenInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.greenBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(text.lastSentence)")
        case .tuk, .note, .separator:
            EmptyView()
        }
    }
}

private extension String {
    /// Only the newest sentence, so Coach shows one line from each side at a time.
    var lastSentence: String {
        let last = CheckInPartner.sentences(in: self).last.map(String.init) ?? self
        return last.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Where today stands, shown after a voice call ends. Styled like the card on Log.
private struct DayCard: View {
    @Environment(CheckInStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let progress = store.progress
        let today = store.log(for: .now)
        let counts: [(Product, Int)] = [
            (.cigarette, progress.cigarettesToday ?? 0),
            (.vape, progress.vapesToday),
            (.pouch, progress.pouchesToday),
        ]
        let logged = counts.filter { $0.1 > 0 }.map { "\($0.1) \($0.0.noun($0.1))" }

        let title: String
        let line: String
        if !logged.isEmpty {
            title = "Today · \(logged.joined(separator: " · "))"
            line = "That's today so far. Thanks for being honest with me."
        } else if progress.loggedToday {
            title = "Today · No nicotine"
            line = "Nothing today. I'm proud of you."
        } else {
            title = "Today · Nothing logged yet"
            line = "Tell me later how the rest of the day goes."
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TukView(stage: max(progress.stage, .cuttingDown))
                    .frame(width: 92, height: 92)
                    .frame(width: 96, height: 96)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.figtree(17, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line)
                        .font(.tuk())
                        .foregroundStyle(Palette.tukInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            let details = [
                today?.cravingLevel.map { "Craving \($0)/10" },
                today?.mood.map { "Feeling \($0.lowercased())" },
                logged.isEmpty && progress.currentStreak > 0 ? "\(progress.currentStreak)-day streak" : nil,
            ].compactMap { $0 }
            if !details.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(details, id: \.self) { Pill(text: $0) }
                }
            }

            HStack(spacing: 10) {
                LeafNote(text: logged.isEmpty
                    ? "Each log helps Tuk learn."
                    : "A slip moves Tuk back one step at most. Never to the start.")
                Spacer(minLength: 0)
                Button("Edit in Log") { router.tab = .log }
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
        .accessibilityElement(children: .contain)
    }
}

private struct AttachmentView: View {
    var attachment: CoachThread.Attachment
    var onBreathe: () -> Void

    var body: some View {
        switch attachment {
        case let .insight(insight):
            InsightCard(insight: insight)
        case let .plan(time):
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(time)
                        .font(.figtree(14, .heavy, relativeTo: .subheadline))
                        .foregroundStyle(Palette.greenInk)
                    Text("Breather with Tuk")
                        .font(.figtree(12, relativeTo: .caption))
                        .foregroundStyle(Palette.greenMuted)
                }
                Spacer(minLength: 0)
                Text("On")
                    .font(.figtree(12, .heavy, relativeTo: .caption))
                    .foregroundStyle(Palette.onGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Palette.green, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.greenSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .breathe:
            Button(action: onBreathe) {
                HStack(spacing: 7) {
                    Text("Breathe with Tuk")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(.figtree(14, .heavy, relativeTo: .subheadline))
                .foregroundStyle(Palette.skyInk)
                .padding(.horizontal, 15)
                .frame(height: 38)
                .background(Palette.sky, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.skyBorder, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
    }
}

/// "Toughest window: 2–4 pm" with a bar per part of the day.
private struct InsightCard: View {
    var insight: CoachThread.Insight

    var body: some View {
        let peak = max(insight.counts.values.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Toughest window")
                    .font(.figtree(12, .heavy, relativeTo: .caption))
                Spacer()
                Text("This week")
                    .font(.figtree(12, .semibold, relativeTo: .caption))
            }
            .foregroundStyle(Palette.inkSecondary)
            Text(insight.window.label)
                .font(.figtree(24, .heavy, relativeTo: .title2))
                .foregroundStyle(Palette.ink)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(UsagePatterns.Window.allCases) { window in
                    let count = insight.counts[window] ?? 0
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(window == insight.window ? Palette.blue : Palette.chipBorder)
                            .frame(height: 5 + 22 * CGFloat(count) / CGFloat(peak))
                        Text(window.shortLabel)
                            .font(.figtree(9, .heavy, relativeTo: .caption2))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(height: 42, alignment: .bottom)
            .accessibilityHidden(true)
            Text("\(insight.inWindow) of \(insight.total) this week\(insight.pattern.map { " · \($0)" } ?? "")")
                .font(.figtree(13, relativeTo: .footnote))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0xF6F1E7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Three bouncing dots in place of Tuk's line while he's working on a reply.
private struct TypingDots: View {
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color(hex: 0x7A6E62))
                    .frame(width: 8, height: 8)
                    .offset(y: bounce ? -3 : 0)
                    .opacity(bounce ? 1 : 0.45)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.15), value: bounce)
            }
        }
        .frame(height: 28)
        .onAppear { bounce = true }
        .accessibilityLabel("Tuk is typing")
    }
}

/// Shown in text mode until the app knows where the LIFTR backend runs.
private struct BackendSetupCard: View {
    var onSave: () -> Void
    @State private var address = "http://localhost:8080"
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Typed coaching isn't connected yet")
                .font(.figtree(15, .heavy, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Text("Start the backend (see backend/README.md) and enter its address. In the simulator on the same Mac, that's http://localhost:8080. You can also add it to LIFTR/Backend.plist.")
                .font(.figtree(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSecondary)
            HStack {
                TextField("https://…", text: $address)
                    .font(.figtree(15, relativeTo: .body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(save)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.chipBorder, lineWidth: 1))
                Button("Save", action: save)
                    .font(.figtree(15, .heavy, relativeTo: .body))
                    .foregroundStyle(Palette.onGreen)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Palette.green, in: Capsule())
                    .disabled(address.isEmpty)
            }
            if invalid {
                Text("That doesn't look like a web address. It starts with http:// or https://.")
                    .font(.figtree(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.tanInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liftrCard(radius: 20, fill: Palette.paper)
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

/// Shown in voice mode until the ElevenLabs agent is set up.
struct AgentSetupCard: View {
    @Environment(CheckInPartner.self) private var partner
    @State private var agentID = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tuk's voice isn't set up yet")
                .font(.figtree(15, .heavy, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Text("Paste your ElevenLabs agent ID below, or add it to LIFTR/ElevenLabs.plist. See docs/elevenlabs-agent.md.")
                .font(.figtree(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSecondary)
            HStack {
                TextField("agent_…", text: $agentID)
                    .font(.figtree(15, relativeTo: .body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(save)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.chipBorder, lineWidth: 1))
                Button("Save", action: save)
                    .font(.figtree(15, .heavy, relativeTo: .body))
                    .foregroundStyle(Palette.onGreen)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Palette.green, in: Capsule())
                    .disabled(agentID.isEmpty)
            }
            if invalid {
                Text("That doesn't look like an agent ID. It starts with agent_.")
                    .font(.figtree(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.tanInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liftrCard(radius: 20, fill: Palette.paper)
    }

    private func save() {
        invalid = !partner.saveAgentID(agentID)
    }
}
