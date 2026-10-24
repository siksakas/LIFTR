//
//  QuickLogView.swift
//  LIFTR Watch App
//

import SwiftUI

/// One big button: tap it when you smoke a cigarette.
struct QuickLogView: View {
    @Environment(WatchLogger.self) private var logger

    var body: some View {
        VStack(spacing: 8) {
            Text(todayText)
                .font(.headline)
                .contentTransition(.numericText())
                .animation(.default, value: logger.cigarettesToday)

            Button(action: logger.logCigarette) {
                VStack(spacing: 4) {
                    Image(systemName: "smoke.fill")
                        .font(.title)
                    Text("I smoked one")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            if logger.undoable != nil {
                Button("Undo", systemImage: "arrow.uturn.backward", action: logger.undo)
                    .buttonStyle(.bordered)
                    .transition(.opacity)
            } else {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.default, value: logger.undoable)
        .padding(.horizontal, 4)
        .navigationTitle("Liftr")
    }

    private var todayText: String {
        let count = logger.cigarettesToday
        return count == 0 ? "None today" : "\(count) today"
    }

    private var footnote: String {
        if let streak = logger.soberStreakDays, logger.cigarettesToday == 0, streak > 0 {
            return "\(streak)-day streak"
        }
        return "Your partner will check in on it."
    }
}

#Preview {
    QuickLogView()
        .environment(WatchLogger())
}
