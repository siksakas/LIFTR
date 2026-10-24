//
//  LiftrBackend.swift
//  LIFTR
//

import Foundation

/// Talks to the Node backend in `backend/`: saves each day's counts to Snowflake and runs the
/// text coach. Optional; the app works offline without it.
///
/// Configured from `LIFTR/ElevenLabs.plist`: `BackendURL`, and `AppToken` if the backend sets
/// `APP_TOKEN`. When `BackendURL` is empty but `ConversationTokenURL` points at the backend's
/// `/elevenlabs/token`, the backend is found from that.
struct LiftrBackend {
    var baseURL: URL
    var appToken: String?

    struct ChatMessage: Encodable {
        var role: String
        var content: String
    }

    enum Failure: LocalizedError {
        case server(String)

        var errorDescription: String? {
            switch self {
            case let .server(message): message
            }
        }
    }

    static func load(bundle: Bundle = .main) -> LiftrBackend? {
        guard
            let url = bundle.url(forResource: "ElevenLabs", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let token = (plist["AppToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let base = (plist["BackendURL"] as? String).flatMap({ $0.isEmpty ? nil : URL(string: $0) }) {
            return LiftrBackend(baseURL: base, appToken: token)
        }
        if let tokenURL = (plist["ConversationTokenURL"] as? String).flatMap(URL.init(string:)),
           tokenURL.path().hasSuffix("/elevenlabs/token") {
            let base = tokenURL.deletingLastPathComponent().deletingLastPathComponent()
            return LiftrBackend(baseURL: base, appToken: token)
        }
        return nil
    }

    /// A random ID for this install, which the backend uses to keep users apart.
    static var userID: String {
        let key = "LiftrUserID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// Saves one day, one row per product, so a correction to 0 overwrites the old number.
    func sync(_ log: DailyLog) async throws {
        for product in Product.allCases {
            var body: [String: Any] = [
                "dayKey": log.dayKey,
                "productType": product.rawValue,
                "quantity": log.count(of: product),
                "source": log.source == "voice" ? "voice" : "manual",
            ]
            if product == .cigarette {
                body["cravingLevel"] = log.cravingLevel
                body["mood"] = log.mood
                body["note"] = log.note
            }
            _ = try await post("logs", json: body)
        }
    }

    /// Asks the coach for a reply. `progress` is what the app already computed.
    func coachReply(to messages: [ChatMessage], progress: RecoveryProgress) async throws -> String {
        let body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "appProgress": [
                "liftr_score": progress.score,
                "tuk_stage": progress.stage.title,
                "sober_streak_days": progress.currentStreak,
                "cigarettes_today": progress.cigarettesToday ?? 0,
                "usual_per_day": progress.baseline,
            ],
        ]
        let response = try await post("coach", json: body)
        guard let reply = response["reply"] as? String else { throw Failure.server("The coach sent back an empty reply.") }
        return reply
    }

    private func post(_ path: String, json: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userID, forHTTPHeaderField: "X-User-Id")
        if let appToken { request.setValue(appToken, forHTTPHeaderField: "X-App-Token") }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await URLSession.shared.data(for: request)
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.server(body["error"] as? String ?? "The LIFTR backend didn't answer.")
        }
        return body
    }
}
