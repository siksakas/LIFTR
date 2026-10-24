//
//  CheckInStore.swift
//  LIFTR
//

import Foundation
import SwiftData

/// Reads and writes logs. The Log screen, the manual log sheet, notifications and the voice
/// partner all go through here.
@Observable
final class CheckInStore {
    private let context: ModelContext
    private(set) var progress: RecoveryProgress
    private(set) var patterns: UsagePatterns

    init(context: ModelContext) {
        self.context = context
        self.progress = RecoveryProgress(days: [])
        self.patterns = UsagePatterns(events: [])
        refresh()
    }

    func log(for date: Date) -> DailyLog? {
        let key = DailyLog.key(for: date)
        var descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates or replaces the cigarette count for `date`. Logging the same day twice overwrites it,
    /// so a user can correct themselves ("actually it was two, not one").
    /// For an existing day, a `nil` detail keeps what was saved and an empty `note` clears it.
    /// Vapes and pouches logged that day are kept.
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
        try save()
        return entry
    }

    /// Adds uses with one tap (or one sentence). Returns the new events so the caller can
    /// attach what set them off, or undo them.
    @discardableResult
    func logUse(_ product: Product, count: Int = 1, source: String = "manual", at date: Date = .now) throws -> [LogEvent] {
        guard count > 0 else { return [] }
        let day: DailyLog
        if let existing = log(for: date) {
            day = existing
        } else {
            day = DailyLog(day: date, cigarettesSmoked: 0, source: source)
            context.insert(day)
        }
        day.setCount(day.count(of: product) + count, of: product)
        day.source = source
        day.updatedAt = .now

        let events = (0..<count).map { _ in LogEvent(kind: LogEvent.Kind(product), timestamp: date, source: source) }
        for event in events { context.insert(event) }
        try save()
        return events
    }

    /// Takes back uses logged with `logUse`.
    func undo(_ events: [LogEvent]) throws {
        var day: DailyLog?
        if let first = events.first, let product = first.product, let existing = log(for: first.timestamp) {
            existing.setCount(existing.count(of: product) - events.count, of: product)
            existing.updatedAt = .now
            day = existing
        }
        for event in events { context.delete(event) }
        try save()
    }

    /// Notes what set off the given uses, like "Stress". `nil` clears it.
    func setTrigger(_ trigger: String?, for events: [LogEvent]) {
        events.forEach { $0.trigger = trigger }
        try? save()
    }

    /// Remembers that a craving hit, so it shows up in when cravings hit.
    func logCraving(source: String = "manual") {
        context.insert(LogEvent(kind: .craving, source: source))
        try? save()
    }

    /// Saves an answer to "How are you feeling?", and puts it on today's log if there is one.
    func logFeeling(_ feeling: String, source: String = "notification") {
        context.insert(LogEvent(kind: .feeling, note: feeling, source: source))
        if let today = log(for: .now) {
            today.mood = feeling
            today.updatedAt = .now
        }
        try? save()
    }

    func refresh() {
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        progress = RecoveryProgress(days: logs.map {
            .init(day: $0.day, cigarettes: $0.cigarettesSmoked, vapes: $0.vapes, pouches: $0.pouches)
        })

        let since = Calendar.current.date(byAdding: .day, value: -31, to: .now)!
        let recent = (try? context.fetch(FetchDescriptor<LogEvent>(predicate: #Predicate { $0.timestamp >= since }))) ?? []
        patterns = UsagePatterns(events: recent.compactMap { event in
            event.kind.map { UsagePatterns.Event(timestamp: event.timestamp, kind: $0, trigger: event.trigger) }
        })
    }

    // MARK: - Sample data

    var hasSampleData: Bool {
        _ = progress
        let source = SampleData.source
        return ((try? context.fetchCount(FetchDescriptor<DailyLog>(predicate: #Predicate { $0.source == source }))) ?? 0) > 0
    }

    /// Fills the last two weeks with `SampleData` for a demo. Days that already have a log
    /// are left as they are.
    func addSampleData(now: Date = .now) throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        for sample in SampleData.days {
            guard let day = calendar.date(byAdding: .day, value: -sample.daysAgo, to: todayStart),
                  log(for: day) == nil else { continue }
            let entry = DailyLog(
                day: day,
                cigarettesSmoked: 0,
                cravingLevel: sample.cravingLevel,
                mood: sample.mood,
                note: sample.note,
                source: SampleData.source
            )
            for moment in sample.moments {
                let time = calendar.date(bySettingHour: moment.hour, minute: moment.minute, second: 0, of: day) ?? day
                context.insert(LogEvent(kind: moment.kind, timestamp: time, trigger: moment.trigger, source: SampleData.source))
                if let product = Product(rawValue: moment.kind.rawValue) {
                    entry.setCount(entry.count(of: product) + 1, of: product)
                }
            }
            context.insert(entry)
        }
        try save()
    }

    /// Takes out everything `addSampleData` added.
    func removeSampleData() throws {
        let source = SampleData.source
        try context.delete(model: DailyLog.self, where: #Predicate { $0.source == source })
        try context.delete(model: LogEvent.self, where: #Predicate { $0.source == source })
        try save()
    }

    /// Saves on the phone, then sends anything that changed to the backend.
    private func save() throws {
        try context.save()
        refresh()
        syncPending()
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
                        vapes: log.vapes,
                        pouches: log.pouches,
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
