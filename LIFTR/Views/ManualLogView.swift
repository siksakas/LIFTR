//
//  ManualLogView.swift
//  LIFTR
//

import SwiftUI

/// Fallback for logging a day without talking to the voice partner.
struct ManualLogView: View {
    @Environment(CheckInStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isYesterday = false
    @State private var cigarettes = 0
    @State private var vapeSessions = 0
    @State private var pouches = 0
    @State private var otherUses = 0
    @State private var cravingLevel = 0.0
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Day", selection: $isYesterday) {
                    Text("Today").tag(false)
                    Text("Yesterday").tag(true)
                }
                .pickerStyle(.segmented)

                Section {
                    CountRow(title: "Cigarettes", count: $cigarettes)
                    CountRow(title: "Vape sessions", count: $vapeSessions)
                    CountRow(title: "Pouches", count: $pouches)
                    CountRow(title: "Other (cigars, gum…)", count: $otherUses)
                } header: {
                    Text("Nicotine")
                } footer: {
                    Text(cigarettes + vapeSessions + pouches + otherUses == 0 ? "All zero means a sober day." : "")
                }

                Section("Cravings") {
                    Slider(value: $cravingLevel, in: 0...10, step: 1)
                    Text("\(Int(cravingLevel)) / 10")
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextField("How did it go?", text: $note, axis: .vertical)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Check in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: loadExisting)
            .onChange(of: isYesterday) { loadExisting() }
        }
    }

    private var date: Date {
        isYesterday ? Calendar.current.date(byAdding: .day, value: -1, to: .now)! : .now
    }

    private func loadExisting() {
        let existing = store.log(for: date)
        cigarettes = existing?.cigarettesSmoked ?? 0
        vapeSessions = existing?.vapeSessions ?? 0
        pouches = existing?.pouches ?? 0
        otherUses = existing?.otherUses ?? 0
        cravingLevel = Double(existing?.cravingLevel ?? 0)
        note = existing?.note ?? ""
    }

    private func save() {
        do {
            try store.record(
                date: date,
                cigarettesSmoked: cigarettes,
                vapeSessions: vapeSessions,
                pouches: pouches,
                otherUses: otherUses,
                cravingLevel: Int(cravingLevel),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                source: "manual"
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CountRow: View {
    var title: String
    @Binding var count: Int

    var body: some View {
        Stepper(value: $count, in: 0...100) {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(count == 0 ? Color.secondary : Color.primary)
            }
        }
    }
}
