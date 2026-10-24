//
//  ContentView.swift
//  LIFTR
//
//  Created by Siksaka Suriyasat on 10/24/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    enum Tab { case today, coach }

    @Environment(CheckInPartner.self) private var partner
    @State private var tab = Tab.today

    var body: some View {
        TabView(selection: $tab) {
            TodayView(onTalk: talk)
                .tabItem { Label("Today", systemImage: "leaf") }
                .tag(Tab.today)
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(Tab.coach)
        }
    }

    /// Opens the Coach tab and starts a voice check-in, if the partner is set up.
    private func talk() {
        tab = .coach
        guard partner.isConfigured else { return }
        Task { await partner.start() }
    }
}

#Preview {
    let container = try! ModelContainer(for: DailyLog.self, VoiceTranscript.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = CheckInStore(context: container.mainContext)
    return ContentView()
        .environment(store)
        .environment(CheckInPartner(store: store))
        .modelContainer(container)
}
