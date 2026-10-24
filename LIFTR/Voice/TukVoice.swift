//
//  TukVoice.swift
//  LIFTR
//

import Foundation

/// A voice Tuk can talk in on Coach calls. These are ElevenLabs' built-in voices, so every
/// account has them. `nil` keeps whatever voice the agent is set to in the dashboard.
struct TukVoice: Identifiable, Hashable {
    var voiceID: String?
    var name: String
    var detail: String

    var id: String { voiceID ?? "agent-default" }

    static let all: [TukVoice] = [
        TukVoice(voiceID: nil, name: "Tuk's usual voice", detail: "The voice set on the agent"),
        TukVoice(voiceID: "bIHbv24MWmeRgasZH58o", name: "Will", detail: "Relaxed, laid back"),
        TukVoice(voiceID: "SAz9YHcvj6GT2YYXdXww", name: "River", detail: "Calm, neutral"),
        TukVoice(voiceID: "XrExE9yKIg1WjnnlVkGX", name: "Matilda", detail: "Upbeat, warm alto"),
        TukVoice(voiceID: "CwhRBWXzGAHq8TQ4Fs17", name: "Roger", detail: "Easygoing, resonant"),
        TukVoice(voiceID: "iP95p4xoKVk53GoZ742B", name: "Chris", detail: "Down-to-earth"),
        TukVoice(voiceID: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice", detail: "Clear, friendly, British"),
        TukVoice(voiceID: "IKne3meq5aSn9XLyUdCD", name: "Charlie", detail: "Energetic, Australian"),
    ]

    /// Where the picked voice ID is kept. Empty means Tuk's usual voice.
    static let savedVoiceIDKey = "TukVoiceID"

    /// The voice ID to ask the agent for on the next call, or nil for the agent's own voice.
    static var savedVoiceID: String? {
        let id = UserDefaults.standard.string(forKey: savedVoiceIDKey) ?? ""
        return id.isEmpty ? nil : id
    }
}
