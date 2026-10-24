//
//  ElevenLabsSettings.swift
//  LIFTR
//

import Foundation

/// Connection settings for the ElevenLabs agent, read from `ElevenLabs.plist` in the app bundle.
///
/// The plist is gitignored so agent IDs and backend URLs stay out of source control.
/// Copy `Config/ElevenLabs.example.plist` to `LIFTR/ElevenLabs.plist` and fill it in.
struct ElevenLabsSettings {
    /// ID of the ElevenLabs agent. Enough on its own for a public agent.
    var agentID: String
    /// Optional backend endpoint that returns `{"token": "..."}` for a private agent.
    /// The backend holds the ElevenLabs API key; the app never does.
    var conversationTokenURL: URL?

    static func load(bundle: Bundle = .main) -> ElevenLabsSettings? {
        guard
            let url = bundle.url(forResource: "ElevenLabs", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let agentID = (plist["AgentID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !agentID.isEmpty,
            !agentID.hasPrefix("YOUR_")
        else { return nil }

        let tokenURL = (plist["ConversationTokenURL"] as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return ElevenLabsSettings(agentID: agentID, conversationTokenURL: tokenURL)
    }
}
