//
//  TodayView.swift
//  LIFTR
//

import SwiftData
import SwiftUI

/// Home screen: pet, streak, score, and today's check-in status.
struct TodayView: View {
    @Environment(CheckInStore.self) private var store
    @Query(sort: \DailyLog.dayKey, order: .reverse) private var logs: [DailyLog]
    @State private var showingManualLog = false
    @State private var confirmingDelete = false
    @State private var dataError: String?
    var onTalk: () -> Void

    var body: some View {
        let progress = store.progress
        NavigationStack {
            List {
                Section {
                    PetCard(progress: progress)
                }

                Section {
                    HStack(spacing: 16) {
                        StatTile(title: "Sober streak", value: "\(progress.currentStreak)", unit: progress.currentStreak == 1 ? "day" : "days")
                        StatTile(title: "Longest", value: "\(progress.longestStreak)", unit: progress.longestStreak == 1 ? "day" : "days")
                    }
                    ScoreRow(score: progress.score)
                }

                Section("Today") {
                    if let today = logs.first(where: { $0.dayKey == DailyLog.key(for: .now) }) {
                        Label(
                            today.isSober ? "Sober today" : "\(today.summary) today",
                            systemImage: today.isSober ? "checkmark.seal.fill" : "smoke"
                        )
                    } else {
                        Text("You haven't checked in yet.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Talk to your partner", systemImage: "waveform", action: onTalk)
                    Button("Log manually", systemImage: "square.and.pencil") { showingManualLog = true }
                }

                if !logs.isEmpty {
                    Section("History") {
                        ForEach(logs.prefix(30)) { log in
                            HistoryRow(log: log)
                        }
                    }
                }
            }
            .navigationTitle("Liftr")
            .sheet(isPresented: $showingManualLog) {
                ManualLogView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Load demo data", systemImage: "wand.and.stars") {
                            perform { try store.loadDemoData() }
                        }
                        Button("Delete all check-ins", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .confirmationDialog("Delete every check-in on this phone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    perform { try store.deleteAllLogs() }
                }
            } message: {
                Text("Your streak and score start over. Check-ins already saved to Snowflake stay there.")
            }
            .alert("Something went wrong", isPresented: Binding(get: { dataError != nil }, set: { if !$0 { dataError = nil } })) {
                Button("OK") { dataError = nil }
            } message: {
                Text(dataError ?? "")
            }
        }
    }
}

extension TodayView {
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            dataError = error.localizedDescription
        }
    }
}

private struct PetCard: View {
    var progress: RecoveryProgress

    var body: some View {
        VStack(spacing: 8) {
            Text(progress.petMood.emoji)
                .font(.system(size: 72))
            Text(Pet.name)
                .font(.title2.bold())
            Text("Feeling \(progress.petMood.rawValue)")
                .foregroundStyle(.secondary)
            ProgressView(value: Double(progress.petHealth), total: 100)
                .tint(progress.petHealth >= 60 ? .green : progress.petHealth >= 30 ? .orange : .red)
            Text("Health \(progress.petHealth)/100")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct StatTile: View {
    var title: String
    var value: String
    var unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title.bold())
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScoreRow: View {
    var score: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Liftr score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(score)")
                    .font(.title3.bold())
                    .monospacedDigit()
            }
            Gauge(
                value: Double(score),
                in: Double(RecoveryProgress.minScore)...Double(RecoveryProgress.maxScore)
            ) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            } minimumValueLabel: {
                Text("\(RecoveryProgress.minScore)").font(.caption2)
            } maximumValueLabel: {
                Text("\(RecoveryProgress.maxScore)").font(.caption2)
            }
            .gaugeStyle(.linearCapacity)
            .tint(Gradient(colors: [.red, .orange, .green]))
        }
    }
}

private struct HistoryRow: View {
    var log: DailyLog

    var body: some View {
        HStack {
            Image(systemName: log.isSober ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(log.isSober ? .green : .orange)
            VStack(alignment: .leading) {
                Text(log.day, format: .dateTime.weekday(.wide).month().day())
                if let note = log.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(log.summary)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
            if log.source == "voice" {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
