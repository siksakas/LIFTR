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
        let day = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates or replaces the log for `date`. Logging the same day twice overwrites it,
    /// so a user can correct themselves ("actually it was two, not one").
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
            existing.note = note ?? existing.note
            existing.source = source
            existing.updatedAt = .now
            entry = existing
        } else {
            entry = DailyLog(
                day: date,
                cigarettesSmoked: cigarettesSmoked,
                cravingLevel: cravingLevel,
                mood: mood,
                note: note,
                source: source
            )
            context.insert(entry)
        }
        try context.save()
        refresh()
        return entry
    }

    func refresh() {
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        progress = RecoveryProgress(days: logs.map { .init(day: $0.day, cigarettes: $0.cigarettesSmoked) })
    }
}
