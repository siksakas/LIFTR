//
//  LIFTRApp.swift
//  LIFTR
//
//  Created by Siksaka Suriyasat on 10/24/26.
//

import SwiftData
import SwiftUI

@main
struct LIFTRApp: App {
    private let container: ModelContainer
    @State private var store: CheckInStore
    @State private var partner: CheckInPartner
    @State private var router: AppRouter
    @State private var reminders: Reminders
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LiftrFonts.register()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: DailyLog.self, LogEvent.self, CircleMember.self, Encouragement.self)
        } catch {
            fatalError("Couldn't open the Liftr database: \(error)")
        }
        let store = CheckInStore(context: container.mainContext)
        let router = AppRouter()
        let reminders = Reminders()
        reminders.activate(router: router, store: store)
        self.container = container
        _store = State(initialValue: store)
        _partner = State(initialValue: CheckInPartner(store: store))
        _router = State(initialValue: router)
        _reminders = State(initialValue: reminders)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(partner)
                .environment(router)
                .environment(reminders)
                .tint(Palette.green)
                // The palette is designed for light backgrounds only.
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) {
            // Streaks depend on what "today" is, so recompute when the app comes back.
            if scenePhase == .active {
                store.refresh()
                store.syncPending()
                Task { await reminders.refreshAuthorization() }
            }
        }
    }
}
