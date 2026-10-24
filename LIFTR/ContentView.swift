//
//  ContentView.swift
//  LIFTR
//
//  Created by Siksaka Suriyasat on 10/24/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            HomeView()
                .tag(AppRouter.Tab.home)
                .toolbar(.hidden, for: .tabBar)
            CoachView()
                .tag(AppRouter.Tab.coach)
                .toolbar(.hidden, for: .tabBar)
            LogView()
                .tag(AppRouter.Tab.log)
                .toolbar(.hidden, for: .tabBar)
            ProgressScreen()
                .tag(AppRouter.Tab.progress)
                .toolbar(.hidden, for: .tabBar)
            CircleView()
                .tag(AppRouter.Tab.circle)
                .toolbar(.hidden, for: .tabBar)
        }
        .overlay(alignment: .bottom) {
            LiftrTabBar(selection: $router.tab)
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard)
        }
        .fullScreenCover(isPresented: $router.showingCravingHelp) {
            CravingHelpView()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: DailyLog.self, LogEvent.self, CircleMember.self, Encouragement.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let store = CheckInStore(context: container.mainContext)
    return ContentView()
        .environment(store)
        .environment(CheckInPartner(store: store))
        .environment(AppRouter())
        .environment(Reminders())
        .modelContainer(container)
}
