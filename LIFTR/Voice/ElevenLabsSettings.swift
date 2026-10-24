//
//  ElevenLabsSettings.swift
//  LIFTR
//

import Foundation

/// Connection settings for the ElevenLabs agent, read from `ElevenLabs.plist` in the app bundle,
/// or from an agent ID pasted into the app's setup card.
///
/// The plist is gitignored so agent IDs and backend URLs stay out of source control.
/// Copy `Config/ElevenLabs.example.plist` to `LIFTR/ElevenLabs.plist` and fill it in.
struct ElevenLabsSettings {
    /// ID of the ElevenLabs agent. Enough on its own for a public agent.
    var agentID: String
    /// Optional backend endpoint that returns `{"token": "..."}` for a private agent.
    /// The backend holds the ElevenLabs API key; the app never does.
    var conversationTokenURL: URL?

    /// UserDefaults key for an agent ID entered in the app instead of the plist.
    static let savedAgentIDKey = "ElevenLabsAgentID"

    static func load(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> ElevenLabsSettings? {
        fromPlist(in: bundle) ?? defaults.string(forKey: savedAgentIDKey)
            .flatMap(normalizedAgentID)
            .map { ElevenLabsSettings(agentID: $0, conversationTokenURL: nil) }
    }

    /// Trims the ID and rejects anything that isn't an ElevenLabs agent ID.
    static func normalizedAgentID(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.hasPrefix("agent_") && id.count > 6 ? id : nil
    }

    private static func fromPlist(in bundle: Bundle) -> ElevenLabsSettings? {
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
