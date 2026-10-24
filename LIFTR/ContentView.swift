//
//  ContentView.swift
//  LIFTR
//
//  Created by Siksaka Suriyasat on 10/24/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    enum Tab { case today, talk, coach }

    @State private var tab = Tab.today

    var body: some View {
        TabView(selection: $tab) {
            TodayView(onTalk: { tab = .talk })
                .tabItem { Label("Today", systemImage: "leaf") }
                .tag(Tab.today)
            CheckInView()
                .tabItem { Label("Talk", systemImage: "waveform") }
                .tag(Tab.talk)
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(Tab.coach)
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: DailyLog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = CheckInStore(context: container.mainContext)
    return ContentView()
        .environment(store)
        .environment(CheckInPartner(store: store))
        .modelContainer(container)
}
