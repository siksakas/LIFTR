//
//  SampleData.swift
//  LIFTR
//

import Foundation

/// Two weeks of made-up logs for demos. The first week is heavier and sets the baseline,
/// then it drops to about one cigarette every couple of days, mostly in the 2–4 pm stretch
/// when work gets stressful, so Coach and Progress have a pattern to point out.
///
/// Everything it adds has the source "sample", so it can be taken out again.
enum SampleData {
    static let source = "sample"

    struct Moment {
        var kind: LogEvent.Kind
        var hour: Int
        var minute: Int
        var trigger: String
    }

    struct Day {
        var daysAgo: Int
        var moments: [Moment]
        var cravingLevel: Int
        var mood: String? = nil
        var note: String? = nil
    }

    private static func cigarette(_ hour: Int, _ minute: Int, _ trigger: String) -> Moment {
        Moment(kind: .cigarette, hour: hour, minute: minute, trigger: trigger)
    }

    private static func vape(_ hour: Int, _ minute: Int, _ trigger: String) -> Moment {
        Moment(kind: .vape, hour: hour, minute: minute, trigger: trigger)
    }

    private static func craving(_ hour: Int, _ minute: Int, _ trigger: String) -> Moment {
        Moment(kind: .craving, hour: hour, minute: minute, trigger: trigger)
    }

    /// Today is left out, so it can be logged live during the demo.
    static let days: [Day] = [
        Day(daysAgo: 14, moments: [
            cigarette(8, 10, "Coffee"), cigarette(10, 45, "Stress"), cigarette(13, 20, "After a meal"),
            cigarette(14, 35, "Stress"), cigarette(15, 50, "Stress"), cigarette(20, 30, "Friends"),
        ], cravingLevel: 8, mood: "stressed"),
        Day(daysAgo: 13, moments: [
            cigarette(8, 20, "Coffee"), cigarette(13, 10, "After a meal"), cigarette(14, 50, "Stress"),
            cigarette(15, 40, "Stress"), cigarette(18, 30, "Bored"), vape(21, 15, "Friends"),
        ], cravingLevel: 7, mood: "okay"),
        Day(daysAgo: 12, moments: [
            cigarette(8, 5, "Coffee"), cigarette(14, 20, "Stress"), cigarette(15, 30, "Stress"),
            cigarette(17, 10, "Bored"), cigarette(20, 45, "Friends"),
        ], cravingLevel: 7, mood: "stressed", note: "Deadline at work."),
        Day(daysAgo: 11, moments: [
            cigarette(8, 30, "Coffee"), cigarette(14, 40, "Stress"), cigarette(15, 55, "Stress"),
            cigarette(19, 20, "After a meal"),
        ], cravingLevel: 6),
        Day(daysAgo: 10, moments: [
            cigarette(8, 15, "Coffee"), cigarette(14, 10, "Stress"), craving(15, 30, "Stress"),
            cigarette(16, 20, "Bored"), cigarette(21, 0, "Friends"),
        ], cravingLevel: 6, mood: "okay"),
        Day(daysAgo: 9, moments: [
            cigarette(8, 40, "Coffee"), cigarette(14, 45, "Stress"), craving(15, 20, "Stress"),
            cigarette(20, 10, "Friends"),
        ], cravingLevel: 5, mood: "good"),
        Day(daysAgo: 8, moments: [
            cigarette(8, 25, "Coffee"), cigarette(13, 15, "After a meal"), craving(14, 30, "Stress"),
            cigarette(15, 5, "Stress"),
        ], cravingLevel: 5, mood: "okay", note: "Tried a walk instead of the 4 pm one."),
        Day(daysAgo: 7, moments: [
            craving(8, 35, "Coffee"), cigarette(14, 50, "Stress"), craving(15, 40, "Stress"),
        ], cravingLevel: 5, mood: "stressed"),
        Day(daysAgo: 6, moments: [
            craving(14, 25, "Stress"), craving(15, 30, "Stress"),
        ], cravingLevel: 4, mood: "proud"),
        Day(daysAgo: 5, moments: [
            craving(8, 30, "Coffee"), cigarette(15, 10, "Stress"),
        ], cravingLevel: 4, mood: "okay"),
        Day(daysAgo: 4, moments: [
            craving(14, 40, "Stress"),
        ], cravingLevel: 3, mood: "good"),
        Day(daysAgo: 3, moments: [
            cigarette(14, 30, "Stress"), craving(20, 15, "Friends"),
        ], cravingLevel: 4, mood: "okay", note: "Rough meeting. Just the one."),
        Day(daysAgo: 2, moments: [
            craving(15, 0, "Stress"),
        ], cravingLevel: 3, mood: "good"),
        Day(daysAgo: 1, moments: [
            craving(14, 45, "Stress"),
        ], cravingLevel: 2, mood: "proud"),
    ]
}
