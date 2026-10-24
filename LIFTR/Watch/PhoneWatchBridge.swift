//
//  PhoneWatchBridge.swift
//  LIFTR
//

import Foundation
#if os(iOS)
import WatchConnectivity
#endif

/// Receives cigarettes tapped on the watch and keeps the watch's count up to date.
///
/// Only does anything on iPhone; on other platforms it's an empty shell so the app still builds.
final class PhoneWatchBridge: NSObject {
    private let store: CheckInStore

    /// Newest watch cigarette saved so far. Sent back to the watch so it knows which of its
    /// taps are already counted in the phone's total.
    private static let syncedThroughKey = "WatchSyncedThrough"
    private var syncedThrough: Date {
        get { UserDefaults.standard.object(forKey: Self.syncedThroughKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncedThroughKey) }
    }

    init(store: CheckInStore) {
        self.store = store
        super.init()
    }

    /// Call once at launch, so taps queued while the app was closed get delivered.
    func activate() {
        #if os(iOS)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        store.onChange = { [weak self] in self?.sendStatus() }
        #endif
    }

    private func apply(_ event: WatchSync.Event) {
        do {
            switch event.kind {
            case .cigarette:
                try store.addCigarette(id: event.id, smokedAt: event.smokedAt, source: "watch")
                syncedThrough = max(syncedThrough, event.smokedAt)
            case .undo:
                try store.removeCigarette(id: event.id)
            }
        } catch {
            print("Liftr: couldn't save a watch cigarette: \(error)")
        }
        sendStatus()
    }

    private func sendStatus() {
        #if os(iOS)
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let progress = store.progress
        let status = WatchSync.Status(
            dayKey: WatchSync.dayKey(for: .now),
            cigarettesToday: progress.cigarettesToday ?? 0,
            soberStreakDays: progress.currentStreak,
            syncedThrough: syncedThrough
        )
        try? session.updateApplicationContext(status.applicationContext)
        #endif
    }
}

#if os(iOS)
extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendStatus() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let event = WatchSync.Event(userInfo: userInfo) else { return }
        Task { @MainActor in self.apply(event) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendStatus() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another watch; start talking to the new one.
        session.activate()
    }
}
#endif
