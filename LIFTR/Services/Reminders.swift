//
//  Reminders.swift
//  LIFTR
//

import Foundation
import Observation
import UserNotifications

/// Tuk's gentle check-ins: a breather just before the toughest time of day, and an optional
/// daily "How are you feeling?". Both are local notifications with quick answers.
@Observable
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    private enum Key {
        static let breatherEnabled = "BreatherEnabled"
        static let breatherWindow = "BreatherWindow"
        static let checkInEnabled = "CheckInEnabled"
        static let checkInMinutes = "CheckInMinutes"
    }

    private enum Category {
        static let breather = "BREATHER"
        static let checkIn = "CHECKIN"
    }

    private enum Action {
        static let breatheNow = "BREATHE_NOW"
        static let notNow = "NOT_NOW"
        static let good = "FEEL_GOOD"
        static let okay = "FEEL_OKAY"
        static let craving = "FEEL_CRAVING"
    }

    private(set) var breatherEnabled: Bool
    /// The window the breather was set up for. It stays put until the user changes it.
    private(set) var breatherWindow: UsagePatterns.Window
    private(set) var checkInEnabled: Bool
    /// Minutes after midnight for the daily check-in. 12:30 pm by default.
    private(set) var checkInMinutes: Int
    /// True when the user turned notifications off for LIFTR in Settings.
    private(set) var isDenied = false

    @ObservationIgnored weak var router: AppRouter?
    @ObservationIgnored weak var store: CheckInStore?
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    override init() {
        let defaults = UserDefaults.standard
        breatherEnabled = defaults.bool(forKey: Key.breatherEnabled)
        breatherWindow = (defaults.object(forKey: Key.breatherWindow) as? Int).flatMap(UsagePatterns.Window.init(rawValue:)) ?? .afternoon
        checkInEnabled = defaults.bool(forKey: Key.checkInEnabled)
        checkInMinutes = defaults.object(forKey: Key.checkInMinutes) as? Int ?? 12 * 60 + 30
        super.init()
    }

    /// Call once at launch, before any notification can be answered.
    func activate(router: AppRouter, store: CheckInStore) {
        self.router = router
        self.store = store
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.breather, actions: [
                UNNotificationAction(identifier: Action.breatheNow, title: "Breathe now", options: [.foreground]),
                UNNotificationAction(identifier: Action.notNow, title: "Not now", options: []),
            ], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.checkIn, actions: [
                UNNotificationAction(identifier: Action.good, title: "Good", options: []),
                UNNotificationAction(identifier: Action.okay, title: "Okay", options: []),
                UNNotificationAction(identifier: Action.craving, title: "Craving", options: [.foreground]),
            ], intentIdentifiers: [], options: []),
        ])
    }

    // MARK: - Settings

    /// "Tuk checks in at 1:55 pm on weekdays"
    func breatherSummary(for window: UsagePatterns.Window) -> String {
        "Tuk checks in at \(Self.timeText(window.breatherTime)) on weekdays"
    }

    func setBreather(_ enabled: Bool, window: UsagePatterns.Window) async {
        if enabled, !(await authorize()) {
            breatherEnabled = false
            return
        }
        breatherEnabled = enabled
        breatherWindow = window
        defaults.set(enabled, forKey: Key.breatherEnabled)
        defaults.set(window.rawValue, forKey: Key.breatherWindow)
        await schedule()
    }

    func setCheckIn(_ enabled: Bool) async {
        if enabled, !(await authorize()) {
            checkInEnabled = false
            return
        }
        checkInEnabled = enabled
        defaults.set(enabled, forKey: Key.checkInEnabled)
        await schedule()
    }

    func setCheckInMinutes(_ minutes: Int) async {
        checkInMinutes = min(max(minutes, 0), 24 * 60 - 1)
        defaults.set(checkInMinutes, forKey: Key.checkInMinutes)
        await schedule()
    }

    /// Re-checks permission, for when the user comes back from Settings.
    func refreshAuthorization() async {
        let status = await center.notificationSettings().authorizationStatus
        isDenied = status == .denied
    }

    private func authorize() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            isDenied = false
            return true
        case .denied:
            isDenied = true
            return false
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            isDenied = !granted
            return granted
        }
    }

    private static let weekdays = 2...6

    private func schedule() async {
        let ids = Self.weekdays.map { "breather-\($0)" } + ["checkin"]
        center.removePendingNotificationRequests(withIdentifiers: ids)

        if breatherEnabled {
            let content = UNMutableNotificationContent()
            content.title = "\(breatherWindow.plural) are usually tough."
            content.body = "Want a 1-minute breather with Tuk?"
            content.sound = .default
            content.categoryIdentifier = Category.breather
            for weekday in Self.weekdays {
                var time = breatherWindow.breatherTime
                time.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
                try? await center.add(UNNotificationRequest(identifier: "breather-\(weekday)", content: content, trigger: trigger))
            }
        }

        if checkInEnabled {
            let content = UNMutableNotificationContent()
            content.title = "How are you feeling?"
            content.body = "Just checking in. One word is enough."
            content.sound = .default
            content.categoryIdentifier = Category.checkIn
            let time = DateComponents(hour: checkInMinutes / 60, minute: checkInMinutes % 60)
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "checkin", content: content, trigger: trigger))
        }
    }

    static func timeText(_ components: DateComponents) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: components.hour, minute: components.minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Answers

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        await handle(action: action, category: category)
    }

    private func handle(action: String, category: String) {
        switch action {
        case Action.breatheNow:
            router?.showingCravingHelp = true
        case Action.notNow, UNNotificationDismissActionIdentifier:
            break
        case Action.good:
            store?.logFeeling("good")
        case Action.okay:
            store?.logFeeling("okay")
        case Action.craving:
            store?.logFeeling("craving")
            router?.showingCravingHelp = true
        default:
            // Tapped the notification itself.
            if category == Category.breather {
                router?.showingCravingHelp = true
            } else {
                router?.tab = .home
            }
        }
    }
}
