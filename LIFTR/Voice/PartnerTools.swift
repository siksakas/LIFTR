//
//  PartnerTools.swift
//  LIFTR
//

import Foundation

/// Client tools the ElevenLabs agent can call during a check-in.
///
/// The tool names and parameters here must match the client tools configured on the
/// agent in the ElevenLabs dashboard (see `docs/elevenlabs-agent.md`).
enum PartnerTools {
    static let logCheckIn = "log_daily_checkin"
    static let getProgress = "get_progress"

    struct Outcome {
        var json: String
        var isError: Bool
        /// Short line for the UI when something was saved.
        var loggedSummary: String?
    }

    static func run(name: String, parameters: [String: Any], store: CheckInStore) -> Outcome {
        switch name {
        case logCheckIn:
            return logDailyCheckIn(parameters, store: store)
        case getProgress:
            return encode(ProgressReport(store.progress))
        default:
            return error("Unknown tool \(name).")
        }
    }

    private static func logDailyCheckIn(_ parameters: [String: Any], store: CheckInStore) -> Outcome {
        guard let cigarettes = int(parameters["cigarettes_smoked"]), cigarettes >= 0 else {
            return error("cigarettes_smoked is required and must be 0 or more. Use 0 for a sober day.")
        }

        let dayName = (parameters["day"] as? String)?.lowercased() ?? "today"
        let date: Date
        switch dayName {
        case "today": date = .now
        case "yesterday": date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        default: return error("day must be \"today\" or \"yesterday\".")
        }

        let craving = int(parameters["craving_level"]).map { min(max($0, 0), 10) }
        let mood = nonEmpty(parameters["mood"])
        let notes = nonEmpty(parameters["notes"])

        let scoreBefore = store.progress.score
        do {
            try store.record(
                date: date,
                cigarettesSmoked: cigarettes,
                cravingLevel: craving,
                mood: mood,
                note: notes,
                source: "voice"
            )
        } catch {
            return Self.error("Couldn't save the check-in: \(error.localizedDescription)")
        }

        var report = ProgressReport(store.progress)
        report.status = "logged"
        report.loggedDay = dayName
        report.loggedCigarettes = cigarettes
        report.scoreChange = store.progress.score - scoreBefore

        var outcome = encode(report)
        let when = dayName == "today" ? "Today" : "Yesterday"
        outcome.loggedSummary = cigarettes == 0
            ? "\(when) logged as sober"
            : "\(when) logged: \(cigarettes) cigarette\(cigarettes == 1 ? "" : "s")"
        return outcome
    }

    // MARK: - Helpers

    /// The agent may send numbers as ints, doubles, or strings.
    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        return string
    }

    private static func encode(_ report: ProgressReport) -> Outcome {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(report) else { return error("Couldn't encode progress.") }
        return Outcome(json: String(decoding: data, as: UTF8.self), isError: false)
    }

    private static func error(_ message: String) -> Outcome {
        let data = (try? JSONEncoder().encode(["error": message])) ?? Data()
        return Outcome(json: String(decoding: data, as: UTF8.self), isError: true)
    }
}

/// What the agent hears back about the user's progress.
struct ProgressReport: Encodable {
    var status = "ok"
    var loggedDay: String?
    var loggedCigarettes: Int?
    var scoreChange: Int?
    var soberStreakDays: Int
    var longestStreakDays: Int
    var totalSoberDays: Int
    var loggedToday: Bool
    var cigarettesToday: Int?
    var cigarettesLast7Days: Int
    var liftrScore: Int
    var liftrScoreRange = "300-850"
    var scoreChangeThisWeek: Int?
    var tukStage: String
    var tukStageNumber: Int
    var petName: String
    var petMood: String

    init(_ progress: RecoveryProgress) {
        soberStreakDays = progress.currentStreak
        longestStreakDays = progress.longestStreak
        totalSoberDays = progress.totalSoberDays
        loggedToday = progress.loggedToday
        cigarettesToday = progress.cigarettesToday
        cigarettesLast7Days = progress.cigarettesLast7Days
        liftrScore = progress.score
        scoreChangeThisWeek = progress.scoreChangeThisWeek
        tukStage = progress.stage.title
        tukStageNumber = progress.stage.rawValue
        petName = TukStage.name
        petMood = progress.stage.mood
    }
}
