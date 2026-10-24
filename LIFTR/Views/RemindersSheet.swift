//
//  RemindersSheet.swift
//  LIFTR
//

import SwiftUI
import UIKit

/// Opened from the bell on Home: Tuk's breather and the daily "How are you feeling?".
struct RemindersSheet: View {
    @Environment(Reminders.self) private var reminders
    @Environment(CheckInStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        let window = reminders.breatherEnabled ? reminders.breatherWindow : (store.patterns.toughestWindow ?? .afternoon)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Gentle nudges from Tuk. Answer right from the notification, no need to open the app.")
                        .font(.figtree(15, relativeTo: .body))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 4)

                    if reminders.isDenied {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications are off for LIFTR.")
                                .font(.figtree(15, .heavy, relativeTo: .headline))
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .font(.figtree(15, .heavy, relativeTo: .body))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liftrCard(fill: Palette.tan)
                    }

                    reminderCard(
                        title: window.breatherName,
                        detail: "\(reminders.breatherSummary(for: window)), just before \(window.label.lowercased()), your toughest time.",
                        preview: "\(window.plural) are usually tough. Want a 1-minute breather with Tuk?",
                        isOn: Binding(
                            get: { reminders.breatherEnabled },
                            set: { on in Task { await reminders.setBreather(on, window: window) } }
                        )
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        reminderCard(
                            title: "Daily check-in",
                            detail: "Tuk asks how you're feeling. Tap Good, Okay or Craving.",
                            preview: "How are you feeling? Just checking in. One word is enough.",
                            isOn: Binding(
                                get: { reminders.checkInEnabled },
                                set: { on in Task { await reminders.setCheckIn(on) } }
                            )
                        )
                        if reminders.checkInEnabled {
                            DatePicker("Time", selection: checkInTime, displayedComponents: .hourAndMinute)
                                .font(.figtree(15, .bold, relativeTo: .body))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .liftrCard(radius: 18)
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("Check-ins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.figtree(16, .heavy, relativeTo: .body))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await reminders.refreshAuthorization() }
    }

    private var checkInTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminders.checkInMinutes / 60, minute: reminders.checkInMinutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                Task { await reminders.setCheckInMinutes((parts.hour ?? 12) * 60 + (parts.minute ?? 30)) }
            }
        )
    }

    private func reminderCard(title: String, detail: String, preview: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.figtree(15, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.figtree(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .tint(Palette.green)

            HStack(alignment: .top, spacing: 10) {
                TukAvatar(stage: .cuttingDown, size: 30, lineWidth: 1)
                Text(preview)
                    .font(.figtree(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Preview: \(preview)")
        }
        .padding(16)
        .liftrCard()
    }
}
