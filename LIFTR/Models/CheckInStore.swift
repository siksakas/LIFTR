//
//  CheckInStore.swift
//  LIFTR
//

import Foundation
import SwiftData

/// Reads and writes daily logs. The manual log sheet, the voice partner and the watch all go through here.
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
        return entry
    }

    // MARK: - Quick-logged cigarettes

    /// Saves one cigarette at the moment it was smoked and adds it to that day's log.
    /// Does nothing if `id` was already saved, since the watch may deliver the same tap twice.
    func addCigarette(id: UUID, smokedAt: Date, source: String) throws {
        guard event(id: id) == nil else { return }
        context.insert(CigaretteEvent(id: id, smokedAt: smokedAt, source: source))

        if let day = log(for: smokedAt) {
            day.cigarettesSmoked += 1
            day.updatedAt = .now
        } else {
            context.insert(DailyLog(day: smokedAt, cigarettesSmoked: 1, source: source))
        }
        try context.save()
        refresh()
    }

    /// Takes back a quick-logged cigarette, e.g. after an accidental tap.
    func removeCigarette(id: UUID) throws {
        guard let event = event(id: id) else { return }
        if let day = log(for: event.smokedAt) {
            day.cigarettesSmoked = max(0, day.cigarettesSmoked - 1)
            day.updatedAt = .now
            // A day that only existed because of this tap shouldn't turn into a "sober" check-in.
            if day.cigarettesSmoked == 0 && day.source == event.source {
                context.delete(day)
            }
        }
        context.delete(event)
        try context.save()
        refresh()
    }

    /// Quick-logged cigarettes after `date`, oldest first.
    func cigarettes(since date: Date) -> [CigaretteEvent] {
        let descriptor = FetchDescriptor<CigaretteEvent>(
            predicate: #Predicate { $0.smokedAt > date },
            sortBy: [SortDescriptor(\.smokedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func event(id: UUID) -> CigaretteEvent? {
        var descriptor = FetchDescriptor<CigaretteEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: -

    /// Called after every change, so the watch can be told the new totals.
    @ObservationIgnored var onChange: (() -> Void)?

    func refresh() {
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        progress = RecoveryProgress(days: logs.map { .init(day: $0.day, cigarettes: $0.cigarettesSmoked) })
        onChange?()
    }
}
