//
//  CoachView.swift
//  LIFTR
//

import SwiftUI

/// Coach Tuk: type, or talk out loud with the ElevenLabs voice partner. Learns only from your logs.
struct CoachView: View {
    enum Mode { case text, voice }

    @Environment(CheckInStore.self) private var store
    @Environment(CheckInPartner.self) private var partner
    @Environment(Reminders.self) private var reminders
    @Environment(AppRouter.self) private var router

    @State private var thread = CoachThread()
    @State private var mode = Mode.text
    @State private var draft = ""
    /// Lines from the current or last voice call that aren't in the thread yet.
    @State private var showsCallLines = false
    @FocusState private var isTyping: Bool

    private let backend = LiftrBackend.load()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(hex: 0xECE4D6))
            conversation
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if mode == .voice, !partner.isConfigured {
                    AgentSetupCard()
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
            if !partner.status.isLive, case .ended = partner.status { foldCallIntoThread() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            TukAvatar(stage: max(store.progress.stage, .cuttingDown), size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach Tuk")
                    .font(.figtree(18, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text("Learns only from your logs")
                    .font(.figtree(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
            }
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
        .frame(height: 56)
        .padding(.top, 4)
        .padding(.bottom, 6)
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
            switchMode(.text)
            isTyping = true
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

    private var conversation: some View {
        let items = thread.items + callItems
        let stage = max(store.progress.stage, .cuttingDown)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        CoachRow(item: item, stage: stage) { router.showingCravingHelp = true }
                            .id(item.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                    }
                    if thread.isTyping || partner.status == .thinking {
                        TypingBubble(stage: stage).id("typing")
                    }
                    if !thread.suggestions.isEmpty, !thread.isTyping {
                        FlowLayout(spacing: 8) {
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
                        .padding(.leading, 38)
                        .id("suggestions")
                        .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.3), value: items)
                .animation(.easeOut(duration: 0.3), value: thread.isTyping)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: items.count) { scrollToBottom(proxy) }
            .onChange(of: items.last) { scrollToBottom(proxy) }
            .onChange(of: thread.isTyping) { scrollToBottom(proxy) }
            .onChange(of: isTyping) { scrollToBottom(proxy) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
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
            thread.append(.note("Typed replies need the LIFTR backend. Add BackendURL to ElevenLabs.plist (see backend/README.md), or switch to Voice."))
            return
        }
        let history = thread.chatHistory
        let progress = store.progress
        Task {
            thread.setTyping(true)
            do {
                let reply = try await backend.coachReply(to: history, progress: progress)
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

// MARK: - Rows

private struct CoachRow: View {
    var item: CoachThread.Item
    var stage: TukStage
    var onBreathe: () -> Void

    var body: some View {
        switch item.kind {
        case let .separator(text):
            Text(text)
                .font(.figtree(12, .bold, relativeTo: .caption))
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity)
        case let .note(text):
            Text(text)
                .font(.figtree(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        case let .me(text):
            Text(text)
                .font(.figtree(15, relativeTo: .body))
                .foregroundStyle(Palette.greenInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.greenBubble, in: MyBubbleShape())
                .frame(maxWidth: 270, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case let .voice(text):
            VStack(alignment: .leading, spacing: 7) {
                WaveformBars(count: 24, idle: Color(hex: 0x5E7C62))
                Text("“\(text)”")
                    .font(.figtree(14, relativeTo: .subheadline))
                    .italic()
                    .foregroundStyle(Palette.greenInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 252, alignment: .leading)
            .background(Palette.greenBubble, in: MyBubbleShape())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(text)")
        case let .tuk(text, attachment):
            HStack(alignment: .bottom, spacing: 8) {
                TukAvatar(stage: stage, size: 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                    if let attachment {
                        AttachmentView(attachment: attachment, onBreathe: onBreathe)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 11)
                .tukBubble(radius: 20)
            }
            .frame(maxWidth: 322, alignment: .leading)
        }
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

private struct TypingBubble: View {
    var stage: TukStage
    @State private var bounce = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TukAvatar(stage: stage, size: 30)
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color(hex: 0x7A6E62))
                        .frame(width: 7, height: 7)
                        .offset(y: bounce ? -3 : 0)
                        .opacity(bounce ? 1 : 0.45)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.15), value: bounce)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.white, in: TukBubbleShape(radius: 20))
            .overlay(TukBubbleShape(radius: 20).stroke(Palette.outline, lineWidth: 1.5))
        }
        .onAppear { bounce = true }
        .accessibilityLabel("Tuk is typing")
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
