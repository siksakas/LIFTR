//
//  WatchSync.swift
//  Shared by LIFTR and LIFTR Watch App
//

import Foundation

/// The messages the watch and phone send each other over WatchConnectivity.
///
/// The watch sends each quick-logged cigarette (and any undo) with `transferUserInfo`, which
/// queues and delivers in order even if the phone app isn't running yet. The phone answers with
/// an application context holding today's total, so the watch always shows the latest count.
///
/// `nonisolated` because the WatchConnectivity delegate callbacks that decode these run off the main actor.
nonisolated enum WatchSync {
    nonisolated enum Kind: String {
        case cigarette
        case undo
    }

    /// One cigarette tapped on the watch, or an undo of one.
    nonisolated struct Event: Equatable, Sendable {
        var kind: Kind
        var id: UUID
        var smokedAt: Date

        var userInfo: [String: Any] {
            ["kind": kind.rawValue, "id": id.uuidString, "smokedAt": smokedAt]
        }

        init(kind: Kind, id: UUID, smokedAt: Date) {
            self.kind = kind
            self.id = id
            self.smokedAt = smokedAt
        }

        init?(userInfo: [String: Any]) {
            guard
                let kind = (userInfo["kind"] as? String).flatMap(Kind.init(rawValue:)),
                let id = (userInfo["id"] as? String).flatMap(UUID.init(uuidString:)),
                let smokedAt = userInfo["smokedAt"] as? Date
            else { return nil }
            self.init(kind: kind, id: id, smokedAt: smokedAt)
        }
    }

    /// What the phone tells the watch after every change.
    nonisolated struct Status: Equatable, Sendable {
        /// "yyyy-MM-dd" of the day `cigarettesToday` belongs to, so a stale count from
        /// yesterday isn't shown as today's.
        var dayKey: String
        var cigarettesToday: Int
        var soberStreakDays: Int
        /// Time of the newest watch cigarette the phone has saved. Anything the watch logged
        /// after this hasn't reached the phone yet, so the watch adds it on top of the count.
        var syncedThrough: Date

        var applicationContext: [String: Any] {
            [
                "dayKey": dayKey,
                "cigarettesToday": cigarettesToday,
                "soberStreakDays": soberStreakDays,
                "syncedThrough": syncedThrough,
            ]
        }

        init(dayKey: String, cigarettesToday: Int, soberStreakDays: Int, syncedThrough: Date) {
            self.dayKey = dayKey
            self.cigarettesToday = cigarettesToday
            self.soberStreakDays = soberStreakDays
            self.syncedThrough = syncedThrough
        }

        init?(applicationContext context: [String: Any]) {
            guard
                let dayKey = context["dayKey"] as? String,
                let cigarettesToday = context["cigarettesToday"] as? Int,
                let soberStreakDays = context["soberStreakDays"] as? Int,
                let syncedThrough = context["syncedThrough"] as? Date
            else { return nil }
            self.init(dayKey: dayKey, cigarettesToday: cigarettesToday, soberStreakDays: soberStreakDays, syncedThrough: syncedThrough)
        }
    }

    /// Same format as `DailyLog.dayKey`.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
