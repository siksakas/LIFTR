//
//  CoachThread.swift
//  LIFTR
//

import Foundation
import Observation

/// The conversation on the Coach tab. Typed messages go to the backend's text coach; voice
/// calls with the ElevenLabs partner are folded into the same thread when they end.
@Observable
final class CoachThread {
    struct Item: Identifiable, Equatable {
        var id = UUID().uuidString
        var kind: Kind

        var isFromUser: Bool {
            switch kind {
            case .me, .voice: true
            case .tuk, .note, .separator: false
            }
        }

        var isFromTuk: Bool {
            if case .tuk = kind { return true }
            return false
        }
    }

    enum Kind: Equatable {
        case separator(String)
        case tuk(String, Attachment?)
        case me(String)
        /// Something the user said on a voice call.
        case voice(String)
        /// A small centred note, like "Today logged as sober".
        case note(String)
    }

    enum Attachment: Equatable {
        case insight(Insight)
        /// "Weekdays · 1:55 pm", once a breather is planned.
        case plan(String)
        /// A button into craving help.
        case breathe
    }

    /// "Toughest window" card, from this week's logs.
    struct Insight: Equatable {
        var window: UsagePatterns.Window
        var counts: [UsagePatterns.Window: Int]
        var total: Int
        var pattern: String?

        var inWindow: Int { counts[window] ?? 0 }
    }

    enum Suggestion: String, CaseIterable {
        case planIt = "Yes, plan it"
        case otherIdeas = "Other ideas"
        case notToday = "Not today"
    }

    private(set) var items: [Item] = []
    private(set) var suggestions: [Suggestion] = []
    private(set) var isTyping = false
    /// The window offered in the opening message, for "Yes, plan it".
    private(set) var offeredWindow: UsagePatterns.Window?

    var hasStarted: Bool { !items.isEmpty }

    /// Tuk opens with what stands out in the week, if anything does.
    func start(patterns: UsagePatterns, reminders: Reminders) {
        guard items.isEmpty else { return }
        items.append(Item(kind: .separator("Today · \(Date.now.formatted(date: .omitted, time: .shortened))")))

        guard let window = patterns.toughestWindowThisWeek else {
            items.append(Item(kind: .tuk("Hi, I'm Coach Tuk. I learn only from your logs, so log a few times this week and I'll look for patterns with you.", nil)))
            items.append(Item(kind: .tuk("How's today going?", nil)))
            return
        }

        let insight = Insight(window: window, counts: patterns.last7Days, total: patterns.totalLast7Days, pattern: patterns.weekPattern)
        items.append(Item(kind: .tuk("I looked at your week. One window stands out:", .insight(insight))))
        if reminders.breatherEnabled, reminders.breatherWindow == window {
            items.append(Item(kind: .tuk("I'll keep checking in just before then. How's today going?", nil)))
        } else {
            items.append(Item(kind: .tuk("What usually happens around then? Want me to check in just before, on weekdays?", nil)))
            offeredWindow = window
            suggestions = Suggestion.allCases
        }
    }

    func append(_ kind: Kind) {
        items.append(Item(kind: kind))
    }

    func append(_ newItems: [Item]) {
        items.append(contentsOf: newItems)
    }

    func clearSuggestions() {
        suggestions = []
    }

    /// Shows the typing dots for a moment, then Tuk's reply.
    func reply(_ kind: Kind, after seconds: Double = 1.1) async {
        isTyping = true
        try? await Task.sleep(for: .seconds(seconds))
        isTyping = false
        items.append(Item(kind: kind))
    }

    func setTyping(_ typing: Bool) {
        isTyping = typing
    }

    /// The conversation so far in the backend's format, newest last.
    var chatHistory: [CoachMessage] {
        let messages = items.compactMap { item -> CoachMessage? in
            switch item.kind {
            case let .tuk(text, _): return CoachMessage(fromUser: false, text: text)
            case let .me(text), let .voice(text): return CoachMessage(fromUser: true, text: text)
            case .separator, .note: return nil
            }
        }
        return Array(messages.suffix(20))
    }
}
