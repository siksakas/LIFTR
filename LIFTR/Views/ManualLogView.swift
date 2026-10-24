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
                    Stepper(value: $cigarettes, in: 0...100) {
                        Text(cigarettes == 0 ? "Sober, no cigarettes" : "\(cigarettes) cigarette\(cigarettes == 1 ? "" : "s")")
                    }
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
        cravingLevel = Double(existing?.cravingLevel ?? 0)
        note = existing?.note ?? ""
    }

    private func save() {
        do {
            try store.record(
                date: date,
                cigarettesSmoked: cigarettes,
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
