//
//  CheckInStore.swift
//  LIFTR
//

import Foundation
import SwiftData

/// Reads and writes daily logs. Both the manual log sheet and the voice partner go through here.
@Observable
final class CheckInStore {
    private let context: ModelContext
    private(set) var progress: RecoveryProgress

    init(context: ModelContext) {
        self.context = context
        self.progress = RecoveryProgress(days: [])
        refresh()
    }

    func log(for date: Date) -> DailyLog? {
        let key = DailyLog.key(for: date)
        var descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates or replaces the log for `date`. Logging the same day twice overwrites it,
    /// so a user can correct themselves ("actually it was two, not one").
    /// For an existing day, a `nil` detail (including the other nicotine types) keeps what was saved,
    /// and an empty `note` clears it.
    @discardableResult
    func record(
        date: Date = .now,
        cigarettesSmoked: Int,
        vapeSessions: Int? = nil,
        pouches: Int? = nil,
        otherUses: Int? = nil,
        cravingLevel: Int? = nil,
        mood: String? = nil,
        note: String? = nil,
        source: String
    ) throws -> DailyLog {
        let entry: DailyLog
        if let existing = log(for: date) {
            existing.cigarettesSmoked = max(0, cigarettesSmoked)
            existing.vapeSessions = vapeSessions.map { max(0, $0) } ?? existing.vapeSessions
            existing.pouches = pouches.map { max(0, $0) } ?? existing.pouches
            existing.otherUses = otherUses.map { max(0, $0) } ?? existing.otherUses
            existing.cravingLevel = cravingLevel ?? existing.cravingLevel
            existing.mood = mood ?? existing.mood
            existing.note = note.map { $0.isEmpty ? nil : $0 } ?? existing.note
            existing.source = source
            existing.updatedAt = .now
            entry = existing
        } else {
            entry = DailyLog(
                day: date,
                cigarettesSmoked: cigarettesSmoked,
                vapeSessions: vapeSessions ?? 0,
                pouches: pouches ?? 0,
                otherUses: otherUses ?? 0,
                cravingLevel: cravingLevel,
                mood: mood,
                note: note?.isEmpty == true ? nil : note,
                source: source
            )
            context.insert(entry)
        }
        try context.save()
        refresh()
        syncPending()
        return entry
    }

    func refresh() {
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        // The score, streak and pet count every kind of nicotine, so a vape day isn't a sober day.
        progress = RecoveryProgress(days: logs.map { .init(day: $0.day, cigarettes: $0.totalUses) })
    }

    // MARK: - Demo data

    /// Fills the 45 days before today with a realistic story for demos: heavy use at first, tapering
    /// down, worse on Fridays and Saturdays, some vaping early on, and a sober streak in the last few days.
    /// Days that already have a log are left alone, and today stays empty so it can be logged live.
    /// The new days sync to Snowflake like any other check-in.
    func loadDemoData() throws {
        var random = SeededRandom(seed: 2026)
        let calendar = Calendar.current
        let moods = ["stressed", "tired", "okay", "anxious", "bored", "proud", "hopeful"]
        let notes = [
            "Coffee and a cigarette with coworkers.",
            "Rough day at work.",
            "Went out with friends, smoked more than planned.",
            "Took a walk instead of a smoke break.",
            "Chewed gum after lunch, it helped.",
            "Craving after dinner was strong.",
        ]

        for daysAgo in 1...45 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now), log(for: day) == nil else { continue }

            let soberStreak = daysAgo <= 5
            // Tapers from about 14 a day, 45 days ago, to about 3 a day just before the streak.
            let base = 3 + Double(14 - 3) * Double(daysAgo - 6) / 39
            let weekday = calendar.component(.weekday, from: day)   // 1 = Sunday ... 7 = Saturday
            let weekendBump = weekday == 6 || weekday == 7 ? 2 : 0
            let total = soberStreak ? 0 : max(1, Int(base.rounded()) + weekendBump + random.int(in: -2...2))

            let vape = !soberStreak && daysAgo > 25 ? min(total / 3, random.int(in: 0...2)) : 0
            let pouch = !soberStreak && (10...25).contains(daysAgo) && random.int(in: 0...3) == 0 ? 1 : 0
            let cigarettes = max(0, total - vape - pouch)
            let craving = soberStreak ? random.int(in: 2...5) : min(10, max(1, total / 2 + random.int(in: 0...3)))

            context.insert(DailyLog(
                day: day,
                cigarettesSmoked: cigarettes,
                vapeSessions: vape,
                pouches: pouch,
                cravingLevel: craving,
                mood: soberStreak ? (random.int(in: 0...1) == 0 ? "proud" : "hopeful") : moods[random.int(in: 0...(moods.count - 1))],
                note: random.int(in: 0...3) == 0 ? notes[random.int(in: 0...(notes.count - 1))] : nil,
                source: "manual"
            ))
        }
        try context.save()
        refresh()
        syncPending()
    }

    /// Deletes every check-in on this phone. Rows already synced to Snowflake stay there.
    func deleteAllLogs() throws {
        try context.delete(model: DailyLog.self)
        try context.save()
        refresh()
    }

    // MARK: - Backend sync

    /// Why the last sync failed, if it did. Cleared by the next successful one.
    private(set) var syncError: String?
    @ObservationIgnored private var isSyncing = false

    /// Sends every log that changed since it was last synced to the backend, which saves it in Snowflake.
    /// Logs always save on the phone first, so a sync that fails (no backend, no signal) is retried
    /// the next time something is logged or the app comes back to the foreground.
    func syncPending() {
        guard !isSyncing, let settings = BackendSettings.load() else { return }
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        let pending = logs.filter { $0.syncedVersion != $0.updatedAt }
        guard !pending.isEmpty else { return }

        isSyncing = true
        let client = BackendClient(settings: settings)
        Task {
            defer { isSyncing = false }
            for log in pending {
                // Remember which version was sent, so an edit made while this request is
                // in flight still counts as unsynced.
                let version = log.updatedAt
                do {
                    try await client.sendLog(
                        dayKey: log.dayKey,
                        cigarettes: log.cigarettesSmoked,
                        vapeSessions: log.vapeSessions,
                        pouches: log.pouches,
                        otherUses: log.otherUses,
                        cravingLevel: log.cravingLevel,
                        mood: log.mood,
                        note: log.note,
                        source: log.source
                    )
                    log.syncedVersion = version
                    syncError = nil
                } catch {
                    syncError = error.localizedDescription
                    break
                }
            }
            try? context.save()
        }
    }
}

/// Small repeatable random numbers, so the demo data comes out the same every time.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return range.lowerBound + Int(z % UInt64(range.count))
    }
}
