//
//  TrendsView.swift
//  LIFTR
//

import Charts
import SwiftData
import SwiftUI

/// Usage over the last 30 days: a chart by nicotine type, averages, and patterns.
struct TrendsView: View {
    @Query private var logs: [DailyLog]

    var body: some View {
        let trends = TrendSummary(logs: logs)
        NavigationStack {
            List {
                if logs.isEmpty {
                    ContentUnavailableView(
                        "No check-ins yet",
                        systemImage: "chart.bar",
                        description: Text("Log a day, or load demo data from the menu on the Today tab.")
                    )
                } else {
                    Section("Last 30 days") {
                        Chart(trends.chart) { point in
                            BarMark(
                                x: .value("Day", point.day, unit: .day),
                                y: .value("Uses", point.count)
                            )
                            .foregroundStyle(by: .value("Type", point.type))
                        }
                        .chartForegroundStyleScale(domain: TrendSummary.types, range: [Color.orange, Color.purple, Color.teal, Color.gray])
                        .frame(height: 200)
                        .padding(.vertical, 8)
                    }

                    Section {
                        LabeledContent("Last 7 days", value: Self.format(trends.averageLast7))
                        LabeledContent("Last 30 days", value: Self.format(trends.averageLast30))
                        LabeledContent("The 30 days before", value: Self.format(trends.averagePrevious30))
                        if let change = trends.changePercent {
                            LabeledContent("Change") {
                                Text(change <= 0 ? "\(change)%" : "+\(change)%")
                                    .foregroundStyle(change <= 0 ? Color.green : Color.orange)
                            }
                        }
                    } header: {
                        Text("Average per logged day")
                    } footer: {
                        Text("Counts every cigarette, vape session, pouch and other use.")
                    }

                    Section("Patterns") {
                        LabeledContent("Sober days", value: "\(trends.soberDaysLast30) of \(trends.loggedDaysLast30) logged")
                        if let weekday = trends.heaviestWeekday {
                            LabeledContent("Heaviest day", value: weekday)
                        }
                        if let craving = trends.averageCravingLast7 {
                            LabeledContent("Cravings, last 7 days", value: String(format: "%.1f / 10", craving))
                        }
                        ForEach(trends.totalsLast30) { total in
                            LabeledContent(total.type, value: "\(total.count) in 30 days")
                        }
                    }
                }
            }
            .navigationTitle("Trends")
        }
    }

    private static func format(_ average: Double?) -> String {
        average.map { String(format: "%.1f", $0) } ?? "–"
    }
}
