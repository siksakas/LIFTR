//
//  BackendClient.swift
//  LIFTR
//

import Foundation

/// One line in the coach chat.
struct CoachMessage: Identifiable, Equatable {
    let id = UUID()
    var fromUser: Bool
    var text: String
}

/// Calls the Liftr backend. See `backend/README.md` for the routes.
struct BackendClient {
    var settings: BackendSettings

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Saves one day's check-in to Snowflake, one row per product, so a correction to 0
    /// overwrites the old number. Sending the same day again overwrites it.
    func sendLog(dayKey: String, cigarettes: Int, vapes: Int, pouches: Int, cravingLevel: Int?, mood: String?, note: String?, source: String) async throws {
        for (product, quantity) in [("cigarette", cigarettes), ("vape", vapes), ("pouch", pouches)] {
            var body: [String: Any] = [
                "dayKey": dayKey,
                "quantity": quantity,
                "productType": product,
                "source": source,
            ]
            // Craving, mood and note describe the day, so they ride along once.
            if product == "cigarette" {
                if let cravingLevel { body["cravingLevel"] = cravingLevel }
                if let mood { body["mood"] = mood }
                if let note { body["note"] = note }
            }
            _ = try await post("logs", body: body)
        }
    }

    /// Asks the AI coach for its next reply. The backend adds the user's trends from Snowflake;
    /// `progress` adds the streak and score the app computes on the phone.
    func coachReply(messages: [CoachMessage], progress: RecoveryProgress) async throws -> String {
        let body: [String: Any] = [
            "messages": messages.map { ["role": $0.fromUser ? "user" : "assistant", "content": $0.text] },
            "appProgress": [
                "liftr_score": progress.score,
                "liftr_score_range": "300-850",
                "sober_streak_days": progress.currentStreak,
                "longest_streak_days": progress.longestStreak,
                "logged_today": progress.loggedToday,
                "cigarettes_today": progress.cigarettesToday.map { $0 as Any } ?? NSNull(),
                "cigarettes_last_7_days": progress.cigarettesLast7Days,
                "tuk_stage": progress.stage.title,
                "pet_mood": progress.stage.mood,
                "usual_per_day": progress.baseline,
                "score_change_this_week": progress.scoreChangeThisWeek.map { $0 as Any } ?? NSNull(),
            ] as [String: Any],
        ]
        let json = try await post("coach", body: body)
        guard let reply = json["reply"] as? String, !reply.isEmpty else {
            throw Failure(message: "The coach sent back an empty reply.")
        }
        return reply
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: settings.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendSettings.userID, forHTTPHeaderField: "X-User-Id")
        if let token = settings.appToken {
            request.setValue(token, forHTTPHeaderField: "X-App-Token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "Couldn't reach the backend at \(settings.baseURL.absoluteString). Is it running?")
        }
        let (data, response) = result
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure(message: json["error"] as? String ?? "The backend returned an error.")
        }
        return json
    }
}
