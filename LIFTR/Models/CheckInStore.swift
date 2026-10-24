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
    /// For an existing day, a `nil` detail keeps what was saved and an empty `note` clears it.
    @discardableResult
    func record(
        date: Date = .now,
        cigarettesSmoked: Int,
        cravingLevel: Int? = nil,
        mood: String? = nil,
        note: String? = nil,
        source: String
    ) throws -> DailyLog {
        let entry: DailyLog
        if let existing = log(for: date) {
            existing.cigarettesSmoked = max(0, cigarettesSmoked)
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
        progress = RecoveryProgress(days: logs.map { .init(day: $0.day, cigarettes: $0.cigarettesSmoked) })
    }

    /// Keeps what was said in a voice check-in, then sends it to the backend with the logs.
    func saveTranscript(_ transcript: VoiceTranscript) {
        context.insert(transcript)
        try? context.save()
        syncPending()
    }

    // MARK: - Backend sync

    /// Why the last sync failed, if it did. Cleared by the next successful one.
    private(set) var syncError: String?
    @ObservationIgnored private var isSyncing = false
    /// Set when something new is saved while a sync is running, so it's sent right after.
    @ObservationIgnored private var syncAgain = false

    /// Sends every log that changed since it was last synced, and every voice transcript not sent yet,
    /// to the backend, which saves them in Snowflake.
    /// Both always save on the phone first, so a sync that fails (no backend, no signal) is retried
    /// the next time something is logged or the app comes back to the foreground.
    func syncPending() {
        guard let settings = BackendSettings.load() else { return }
        guard !isSyncing else {
            syncAgain = true
            return
        }
        syncAgain = false
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        let pendingLogs = logs.filter { $0.syncedVersion != $0.updatedAt }
        let pendingTranscripts = (try? context.fetch(FetchDescriptor<VoiceTranscript>(
            predicate: #Predicate { $0.syncedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        ))) ?? []
        guard !pendingLogs.isEmpty || !pendingTranscripts.isEmpty else { return }

        isSyncing = true
        let client = BackendClient(settings: settings)
        Task {
            defer {
                isSyncing = false
                if syncAgain { syncPending() }
            }
            do {
                for log in pendingLogs {
                    // Remember which version was sent, so an edit made while this request is
                    // in flight still counts as unsynced.
                    let version = log.updatedAt
                    try await client.sendLog(
                        dayKey: log.dayKey,
                        cigarettes: log.cigarettesSmoked,
                        cravingLevel: log.cravingLevel,
                        mood: log.mood,
                        note: log.note,
                        source: log.source
                    )
                    log.syncedVersion = version
                }
                for transcript in pendingTranscripts {
                    try await client.sendTranscript(transcript)
                    transcript.syncedAt = .now
                }
                syncError = nil
            } catch {
                syncError = error.localizedDescription
            }
            try? context.save()
        }
    }
}
