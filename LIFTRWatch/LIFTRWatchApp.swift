//
//  LIFTRWatchApp.swift
//  LIFTR Watch App
//

import SwiftUI

@main
struct LIFTRWatchApp: App {
    @State private var logger = WatchLogger()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            QuickLogView()
                .environment(logger)
        }
        .onChange(of: scenePhase) {
            // "Today" may have changed since the app was last open.
            if scenePhase == .active { logger.prune() }
        }
    }
}
