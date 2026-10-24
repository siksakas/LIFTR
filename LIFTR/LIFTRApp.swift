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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: DailyLog.self, VoiceTranscript.self)
        } catch {
            fatalError("Couldn't open the Liftr database: \(error)")
        }
        let store = CheckInStore(context: container.mainContext)
        self.container = container
        _store = State(initialValue: store)
        _partner = State(initialValue: CheckInPartner(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(partner)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) {
            // Streaks depend on what "today" is, so recompute when the app comes back.
            if scenePhase == .active {
                store.refresh()
                store.syncPending()
            }
        }
    }
}
