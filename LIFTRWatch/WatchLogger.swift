//
//  WatchLogger.swift
//  LIFTR Watch App
//

import Foundation
import WatchConnectivity
import WatchKit

/// Sends cigarettes tapped on the watch to the phone, where they're saved and counted.
///
/// The phone owns the data. The watch only remembers taps the phone hasn't confirmed yet,
/// so it can show the right count while the phone is out of reach.
@Observable
final class WatchLogger: NSObject {
    struct Tap: Codable, Equatable {
        var id: UUID
        var smokedAt: Date
    }

    /// Latest totals from the phone, if it has sent any.
    private(set) var status: WatchSync.Status?
    /// Taps sent but not yet counted in `status`.
    private(set) var pending: [Tap] = []
    /// The most recent tap, while it can still be undone.
    private(set) var undoable: Tap?

    private static let pendingKey = "PendingTaps"
    @ObservationIgnored private var undoTimer: Task<Void, Never>?

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey),
           let taps = try? JSONDecoder().decode([Tap].self, from: data) {
            pending = taps
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Cigarettes smoked today: what the phone has saved plus taps still on their way.
    var cigarettesToday: Int {
        let today = WatchSync.dayKey(for: .now)
        let saved = status?.dayKey == today ? status?.cigarettesToday ?? 0 : 0
        let syncedThrough = status?.syncedThrough ?? .distantPast
        return saved + pending.filter { $0.smokedAt > syncedThrough && WatchSync.dayKey(for: $0.smokedAt) == today }.count
    }

    var soberStreakDays: Int? {
        status?.soberStreakDays
    }

    func logCigarette() {
        let tap = Tap(id: UUID(), smokedAt: .now)
        pending.append(tap)
        save()
        send(.init(kind: .cigarette, id: tap.id, smokedAt: tap.smokedAt))
        WKInterfaceDevice.current().play(.success)

        undoable = tap
        undoTimer?.cancel()
        undoTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.undoable = nil
        }
    }

    func undo() {
        guard let tap = undoable else { return }
        undoable = nil
        undoTimer?.cancel()
        pending.removeAll { $0.id == tap.id }
        save()
        // Transfers arrive in order, so the phone always sees the cigarette before its undo.
        send(.init(kind: .undo, id: tap.id, smokedAt: tap.smokedAt))
        WKInterfaceDevice.current().play(.click)
    }

    /// Drops taps the phone has already counted, and old ones that can't matter for today.
    func prune() {
        let syncedThrough = status?.syncedThrough ?? .distantPast
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let kept = pending.filter { $0.smokedAt > syncedThrough && $0.smokedAt > cutoff }
        if kept != pending {
            pending = kept
            save()
        }
    }

    private func send(_ event: WatchSync.Event) {
        // transferUserInfo queues the event and delivers it whenever the phone is reachable,
        // even if the Liftr app on the phone isn't open.
        WCSession.default.transferUserInfo(event.userInfo)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }

    private func receive(_ status: WatchSync.Status) {
        self.status = status
        prune()
    }
}

extension WatchLogger: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard let status = WatchSync.Status(applicationContext: session.receivedApplicationContext) else { return }
        Task { @MainActor in self.receive(status) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let status = WatchSync.Status(applicationContext: applicationContext) else { return }
        Task { @MainActor in self.receive(status) }
    }
}
