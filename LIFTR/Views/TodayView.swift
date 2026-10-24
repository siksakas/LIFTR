//
//  TodayView.swift
//  LIFTR
//

import SwiftData
import SwiftUI

/// Home screen: pet, streak, score, and today's check-in status.
struct TodayView: View {
    @Environment(CheckInStore.self) private var store
    @Query(sort: \DailyLog.day, order: .reverse) private var logs: [DailyLog]
    @State private var showingManualLog = false
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
                    if let cigarettes = progress.cigarettesToday {
                        Label(
                            cigarettes == 0 ? "Sober today" : "\(cigarettes) cigarette\(cigarettes == 1 ? "" : "s") today",
                            systemImage: cigarettes == 0 ? "checkmark.seal.fill" : "smoke"
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
            Text(log.isSober ? "Sober" : "\(log.cigarettesSmoked) smoked")
                .foregroundStyle(.secondary)
            if log.source == "voice" {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
